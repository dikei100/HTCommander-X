/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public class AprsEntry
    {
        public string Time { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public string Message { get; set; }
    }

    public partial class AprsTabControl : UserControl
    {
        private DataBrokerClient broker;
        private ObservableCollection<AprsEntry> aprsMessages = new ObservableCollection<AprsEntry>();

        public AprsTabControl()
        {
            InitializeComponent();
            AprsGrid.ItemsSource = aprsMessages;

            broker = new DataBrokerClient();
            broker.Subscribe(1, "AprsFrame", OnAprsFrame);
            broker.Subscribe(1, "AprsPacketList", OnAprsPacketList);
            broker.Subscribe(0, new[] { "CallSign", "StationId", "AllowTransmit" }, OnSettingsChanged);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
        }

        private void OnAprsFrame(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                // TODO: Parse APRS frame and add to list
            });
        }

        private void OnAprsPacketList(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Populate from stored packets */ });
        }

        private void OnSettingsChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                if (name == "CallSign" && data is string callsign)
                {
                    CallSignLabel.Text = callsign;
                }
                else if (name == "AllowTransmit" && data is bool allow)
                {
                    TransmitPanel.IsVisible = allow;
                }
            });
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update radio state */ });
        }

        private void ConfigButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Open APRS configuration dialog
        }

        private void SendAprsButton_Click(object sender, RoutedEventArgs e)
        {
            string msg = AprsMessageBox.Text?.Trim();
            if (string.IsNullOrEmpty(msg)) return;
            // TODO: Send APRS message via DataBroker
            AprsMessageBox.Text = "";
        }
    }
}
