using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class TerminalConnectDialog : Window
    {
        private DataBrokerClient broker;
        public int SelectedDeviceId { get; private set; } = -1;
        public string SelectedRadioName { get; private set; }

        public TerminalConnectDialog()
        {
            InitializeComponent();
            broker = new DataBrokerClient();
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            LoadRadios();
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => LoadRadios());
        }

        private void LoadRadios()
        {
            RadioList.Items.Clear();
            var radios = DataBroker.GetValue<object>(1, "ConnectedRadios");
            if (radios is System.Collections.IList list)
            {
                foreach (var radio in list)
                {
                    var type = radio.GetType();
                    var deviceIdProp = type.GetProperty("DeviceId");
                    var nameProp = type.GetProperty("FriendlyName");
                    if (deviceIdProp != null)
                    {
                        int id = (int)deviceIdProp.GetValue(radio);
                        string rname = nameProp?.GetValue(radio)?.ToString() ?? $"Radio {id}";
                        RadioList.Items.Add(new ListBoxItem { Content = rname, Tag = id });
                    }
                }
            }
        }

        private void RadioList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            ConnectButton.IsEnabled = RadioList.SelectedItem != null;
        }

        private void ConnectButton_Click(object sender, RoutedEventArgs e)
        {
            if (RadioList.SelectedItem is ListBoxItem item)
            {
                SelectedDeviceId = (int)item.Tag;
                SelectedRadioName = item.Content?.ToString();
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
