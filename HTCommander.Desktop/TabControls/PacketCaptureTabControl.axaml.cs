/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public class PacketEntry
    {
        public string Time { get; set; }
        public string Channel { get; set; }
        public string Data { get; set; }
        public object RawPacket { get; set; }
    }

    public partial class PacketCaptureTabControl : UserControl
    {
        private DataBrokerClient broker;
        private ObservableCollection<PacketEntry> packets = new ObservableCollection<PacketEntry>();

        public PacketCaptureTabControl()
        {
            InitializeComponent();
            PacketsGrid.ItemsSource = packets;

            broker = new DataBrokerClient();
            broker.Subscribe(1, "PacketStored", OnPacketStored);
            broker.Subscribe(1, "PacketList", OnPacketList);
            broker.Subscribe(1, "PacketStoreReady", OnPacketStoreReady);
        }

        private void OnPacketStoreReady(int deviceId, string name, object data)
        {
            DataBroker.Dispatch(1, "RequestPacketList", null, store: false);
        }

        private void OnPacketList(int deviceId, string name, object data)
        {
            // TODO: Populate from stored packet list
        }

        private void OnPacketStored(int deviceId, string name, object data)
        {
            if (data is TncDataFragment fragment)
            {
                Dispatcher.UIThread.Post(() =>
                {
                    var entry = new PacketEntry
                    {
                        Time = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                        Channel = fragment.channel_name ?? "",
                        Data = Utils.TncDataFragmentToShortString(fragment),
                        RawPacket = fragment
                    };
                    packets.Insert(0, entry);
                    PacketCount.Text = $"{packets.Count} packets";
                });
            }
        }

        private void PacketsGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (PacketsGrid.SelectedItem is PacketEntry entry)
            {
                DecodeText.Text = entry.Data;
            }
        }

        private void ShowDecode_Click(object sender, RoutedEventArgs e)
        {
            // Toggle decode panel visibility
            DataBroker.Dispatch(0, "ShowPacketDecode", ShowDecodeCheck.IsChecked == true);
        }

        private void ClearButton_Click(object sender, RoutedEventArgs e)
        {
            packets.Clear();
            PacketCount.Text = "0 packets";
            DecodeText.Text = "";
        }
    }
}
