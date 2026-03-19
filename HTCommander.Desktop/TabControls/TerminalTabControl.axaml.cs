/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public partial class TerminalTabControl : UserControl
    {
        private DataBrokerClient broker;
        private bool connected = false;

        public TerminalTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);
            broker.Subscribe(DataBroker.AllDevices, "UniqueDataFrame", OnUniqueDataFrame);
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                // Update UI based on connected radios
            });
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                // Update connection status
            });
        }

        private void OnUniqueDataFrame(int deviceId, string name, object data)
        {
            if (data is TncDataFragment fragment)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    string decoded = Utils.TncDataFragmentToShortString(fragment);
                    AppendOutput($"< {decoded}\n");
                });
            }
        }

        private void AppendOutput(string text)
        {
            string current = TerminalOutput.Text ?? "";
            if (current.Length > 100000)
            {
                current = current.Substring(current.Length - 50000);
            }
            TerminalOutput.Text = current + text;
            TerminalOutput.CaretIndex = TerminalOutput.Text.Length;
        }

        private void ConnectButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Open terminal connect dialog
            connected = !connected;
            ConnectButton.Content = connected ? "Disconnect" : "Connect";
            ConnectionStatus.Text = connected ? "Connected" : "Disconnected";
            SendButton.IsEnabled = connected;
        }

        private void SendButton_Click(object sender, RoutedEventArgs e)
        {
            SendMessage();
        }

        private void InputBox_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                SendMessage();
                e.Handled = true;
            }
        }

        private void SendMessage()
        {
            string text = InputBox.Text?.Trim();
            if (string.IsNullOrEmpty(text)) return;

            AppendOutput($"> {text}\n");
            InputBox.Text = "";

            // TODO: Send via DataBroker to connected radio
        }
    }
}
