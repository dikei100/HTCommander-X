/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public partial class BbsTabControl : UserControl
    {
        private DataBrokerClient broker;

        public BbsTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);
            broker.Subscribe(DataBroker.AllDevices, new[] { "BbsTraffic", "BbsControlMessage", "BbsError" }, OnBbsEvent);
            broker.Subscribe(1, "BbsMergedStats", OnBbsMergedStats);
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update radio list */ });
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update lock state */ });
        }

        private void OnBbsEvent(int deviceId, string name, object data)
        {
            if (data is string msg)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    string prefix = name == "BbsError" ? "[ERR] " : "";
                    TrafficLog.Text += $"{prefix}{msg}\n";
                });
            }
        }

        private void OnBbsMergedStats(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update BBS stats grid */ });
        }

        private void ActivateButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Activate/deactivate BBS
        }
    }
}
