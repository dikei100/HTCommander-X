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
    public partial class TorrentTabControl : UserControl
    {
        private DataBrokerClient broker;

        public TorrentTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(0, "TorrentFiles", OnTorrentFilesUpdate);
            broker.Subscribe(0, "TorrentFileUpdate", OnTorrentFileUpdate);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
        }

        private void OnTorrentFilesUpdate(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Populate torrent list */ });
        }

        private void OnTorrentFileUpdate(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update individual torrent */ });
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update radio list */ });
        }

        private void ActivateButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Activate/deactivate torrent
        }
    }
}
