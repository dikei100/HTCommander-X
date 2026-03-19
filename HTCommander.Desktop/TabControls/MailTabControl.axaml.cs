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
    public partial class MailTabControl : UserControl
    {
        private DataBrokerClient broker;

        public MailTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(0, new[] { "MailsChanged", "MailList", "MailShowPreview", "MailStoreReady", "DataHandlerAdded" }, OnMailEvent);
            broker.Subscribe(1, "WinlinkBusy", OnWinlinkBusyChanged);
            broker.Subscribe(1, "WinlinkStateMessage", OnWinlinkStateMessageChanged);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
        }

        private void OnMailEvent(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update mail UI */ });
        }

        private void OnWinlinkBusyChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                ConnectButton.IsEnabled = data is bool b && !b;
            });
        }

        private void OnWinlinkStateMessageChanged(int deviceId, string name, object data)
        {
            // Status message update
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update radio list */ });
        }

        private void MailboxTree_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            // TODO: Load mail list for selected mailbox
        }

        private void MailList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            // TODO: Show preview of selected mail
        }

        private void ComposeButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Open compose dialog
        }

        private void ConnectButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Connect to Winlink
        }
    }
}
