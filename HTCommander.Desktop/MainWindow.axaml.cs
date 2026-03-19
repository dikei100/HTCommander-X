/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Linq;
using System.Collections.Generic;
using System.Threading;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;
using HTCommander.Desktop.Dialogs;

namespace HTCommander.Desktop
{
    public partial class MainWindow : Window
    {
        private DataBrokerClient broker;
        private List<Radio> connectedRadios = new List<Radio>();
        private const int StartingDeviceId = 100;
        private bool dataHandlersInitialized = false;

        public MainWindow()
        {
            InitializeComponent();

            if (SynchronizationContext.Current != null)
            {
                DataBroker.SetSyncContext(SynchronizationContext.Current);
            }

            broker = new DataBrokerClient();
            InitializeDataHandlers();

            // Subscribe to radio state changes for status bar
            broker.Subscribe(DataBroker.AllDevices, "State", OnRadioStateChanged);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            broker.LogInfo("HTCommander Desktop (Avalonia) started. Ready to connect.");
        }

        private void InitializeDataHandlers()
        {
            if (dataHandlersInitialized) return;
            dataHandlersInitialized = true;

            DataBroker.AddDataHandler("FrameDeduplicator", new FrameDeduplicator());
            DataBroker.AddDataHandler("SoftwareModem", new SoftwareModem());
            DataBroker.AddDataHandler("PacketStore", new PacketStore());
            DataBroker.AddDataHandler("VoiceHandler", new VoiceHandler(Program.PlatformServices?.Speech));
            DataBroker.AddDataHandler("LogStore", new LogStore());
            DataBroker.AddDataHandler("AprsHandler", new AprsHandler());
            DataBroker.AddDataHandler("Torrent", new Torrent());
            DataBroker.AddDataHandler("BbsHandler", new BbsHandler());
            DataBroker.AddDataHandler("MailStore", new MailStore());
            DataBroker.AddDataHandler("WinlinkClient", new WinlinkClient());
            DataBroker.AddDataHandler("AirplaneHandler", new HTCommander.Airplanes.AirplaneHandler());
            DataBroker.AddDataHandler("GpsSerialHandler", new HTCommander.Gps.GpsSerialHandler());
        }

        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                // Radio dispatches state as a string (e.g. "Connected")
                string stateStr = data?.ToString() ?? "";
                switch (stateStr)
                {
                    case "Connected":
                        StatusText.Text = $"Radio {deviceId}: Connected";
                        ConnectButton.IsEnabled = true;
                        DisconnectButton.IsEnabled = true;
                        break;
                    case "Connecting":
                        StatusText.Text = $"Radio {deviceId}: Connecting...";
                        break;
                    case "Disconnected":
                        StatusText.Text = connectedRadios.Count > 0 ? $"Radio {deviceId}: Disconnected" : "Not connected";
                        ConnectButton.IsEnabled = true;
                        DisconnectButton.IsEnabled = false;
                        break;
                    case "UnableToConnect":
                        StatusText.Text = $"Radio {deviceId}: Unable to connect";
                        ConnectButton.IsEnabled = true;
                        ShowCantConnectDialog();
                            break;
                        case "BluetoothNotAvailable":
                        StatusText.Text = "Bluetooth not available";
                        ConnectButton.IsEnabled = true;
                        ShowBluetoothActivateDialog();
                        break;
                }
            });
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            // Update the connected radios list in DataBroker
        }

        private async void ConnectButton_Click(object sender, RoutedEventArgs e)
        {
            var platform = Program.PlatformServices;
            if (platform == null)
            {
                broker.LogError("Platform services not initialized.");
                return;
            }

            // Use a temporary IRadioBluetooth for scanning
            var scanner = platform.CreateRadioBluetooth(null);

            try
            {
                broker.LogInfo("Checking Bluetooth...");
                bool btAvailable = await scanner.CheckBluetoothAsync();
                if (!btAvailable)
                {
                    broker.LogError("Bluetooth is not available.");
                    scanner.Dispose();
                    ShowBluetoothActivateDialog();
                    return;
                }

                broker.LogInfo("Scanning for compatible devices...");
                var devices = await scanner.FindCompatibleDevices();
                scanner.Dispose();

                if (devices.Length == 0)
                {
                    broker.LogInfo("No compatible radio devices found. Make sure your radio is paired.");
                    return;
                }

                broker.LogInfo($"Found {devices.Length} device(s).");

                if (devices.Length == 1)
                {
                    // Auto-connect to single device
                    ConnectToRadio(devices[0]);
                }
                else
                {
                    // Show selection dialog
                    var dialog = new RadioConnectionDialog(devices);
                    await dialog.ShowDialog(this);

                    if (dialog.ConnectRequested && dialog.SelectedMac != null)
                    {
                        var target = devices.First(d => d.mac == dialog.SelectedMac);
                        ConnectToRadio(target);
                    }
                    else if (dialog.DisconnectRequested && dialog.SelectedMac != null)
                    {
                        var radio = connectedRadios.FirstOrDefault(r =>
                            r.MacAddress.Equals(dialog.SelectedMac, StringComparison.OrdinalIgnoreCase));
                        if (radio != null)
                        {
                            DisconnectRadio(radio);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                broker.LogError($"Connection error: {ex.Message}");
            }
        }

        private void ConnectToRadio(CompatibleDevice device)
        {
            // Check if already connected
            if (connectedRadios.Any(r => r.MacAddress.Equals(device.mac, StringComparison.OrdinalIgnoreCase)))
            {
                broker.LogInfo($"Already connected to {device.name}.");
                return;
            }

            int deviceId = GetNextAvailableDeviceId();
            broker.LogInfo($"Connecting to {device.name} ({device.mac}) as device {deviceId}...");

            var radio = new Radio(deviceId, device.mac, Program.PlatformServices);
            radio.UpdateFriendlyName(device.name);

            string handlerName = "Radio_" + deviceId;
            DataBroker.AddDataHandler(handlerName, radio);
            connectedRadios.Add(radio);

            // Publish the connected radios list
            DataBroker.Dispatch(1, "ConnectedRadios", connectedRadios.ToArray(), store: true);

            ConnectButton.IsEnabled = false;
            StatusText.Text = $"Connecting to {device.name}...";
            radio.Connect();
        }

        private void DisconnectRadio(Radio radio)
        {
            broker.LogInfo($"Disconnecting radio {radio.DeviceId}...");
            radio.Disconnect();

            string handlerName = "Radio_" + radio.DeviceId;
            DataBroker.RemoveDataHandler(handlerName);
            connectedRadios.Remove(radio);

            DataBroker.Dispatch(1, "ConnectedRadios", connectedRadios.ToArray(), store: true);

            if (connectedRadios.Count == 0)
            {
                StatusText.Text = "Not connected";
                DisconnectButton.IsEnabled = false;
            }
        }

        private void DisconnectButton_Click(object sender, RoutedEventArgs e)
        {
            foreach (var radio in connectedRadios.ToArray())
            {
                DisconnectRadio(radio);
            }
            ConnectButton.IsEnabled = true;
        }

        private int GetNextAvailableDeviceId()
        {
            int id = StartingDeviceId;
            foreach (var radio in connectedRadios)
            {
                if (radio.DeviceId >= id) id = radio.DeviceId + 1;
            }
            return id;
        }

        private async void ShowBluetoothActivateDialog()
        {
            var dialog = new BluetoothActivateDialog();
            await dialog.ShowDialog(this);
        }

        private async void ShowCantConnectDialog()
        {
            var dialog = new CantConnectDialog();
            await dialog.ShowDialog(this);
        }

        protected override void OnClosed(EventArgs e)
        {
            // Disconnect all radios
            foreach (var radio in connectedRadios.ToArray())
            {
                try { radio.Disconnect(); } catch { }
                try { radio.Dispose(); } catch { }
            }
            connectedRadios.Clear();

            broker?.Dispose();
            DataBroker.RemoveAllDataHandlers();
            base.OnClosed(e);
        }
    }
}
