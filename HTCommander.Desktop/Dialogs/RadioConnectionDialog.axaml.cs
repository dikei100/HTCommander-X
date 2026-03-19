using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public class RadioListEntry
    {
        public string Name { get; set; }
        public string Mac { get; set; }
        public string State { get; set; }
    }

    public partial class RadioConnectionDialog : Window
    {
        private DataBrokerClient broker;
        private ObservableCollection<RadioListEntry> radioEntries = new ObservableCollection<RadioListEntry>();
        private CompatibleDevice[] devices;

        public string SelectedMac { get; private set; }
        public string SelectedName { get; private set; }
        public bool ConnectRequested { get; private set; }
        public bool DisconnectRequested { get; private set; }

        public RadioConnectionDialog(CompatibleDevice[] devices)
        {
            InitializeComponent();
            this.devices = devices;
            RadiosGrid.ItemsSource = radioEntries;

            broker = new DataBrokerClient();
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "RadioState", OnRadioStateChanged);

            PopulateDevices();
        }

        private void PopulateDevices()
        {
            radioEntries.Clear();
            foreach (var device in devices)
            {
                radioEntries.Add(new RadioListEntry
                {
                    Name = device.name,
                    Mac = device.mac,
                    State = "Available"
                });
            }
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => UpdateStates());
        }

        private void OnRadioStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => UpdateStates());
        }

        private void UpdateStates()
        {
            // TODO: Update state column from connected radios
        }

        private void RadiosGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            bool hasSelection = RadiosGrid.SelectedItem is RadioListEntry;
            ConnectButton.IsEnabled = hasSelection;
            DisconnectButton.IsEnabled = hasSelection;
        }

        private void ConnectButton_Click(object sender, RoutedEventArgs e)
        {
            if (RadiosGrid.SelectedItem is RadioListEntry entry)
            {
                SelectedMac = entry.Mac;
                SelectedName = entry.Name;
                ConnectRequested = true;
                Close();
            }
        }

        private void DisconnectButton_Click(object sender, RoutedEventArgs e)
        {
            if (RadiosGrid.SelectedItem is RadioListEntry entry)
            {
                SelectedMac = entry.Mac;
                SelectedName = entry.Name;
                DisconnectRequested = true;
                Close();
            }
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
