/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public partial class ContactsTabControl : UserControl
    {
        private DataBrokerClient broker;

        public ContactsTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();
            broker.Subscribe(0, "Stations", OnStationsChanged);
        }

        private void OnStationsChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                if (data is List<StationInfoClass> stations)
                {
                    StationsGrid.ItemsSource = stations;
                }
            });
        }

        private void StationsGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            bool hasSelection = StationsGrid.SelectedItem != null;
            EditButton.IsEnabled = hasSelection;
            RemoveButton.IsEnabled = hasSelection;
        }

        private void AddButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Open station add dialog
        }

        private void EditButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Open station edit dialog
        }

        private void RemoveButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Remove selected station
        }
    }
}
