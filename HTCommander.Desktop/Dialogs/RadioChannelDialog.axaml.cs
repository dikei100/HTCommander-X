using System;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioChannelDialog : Window
    {
        private int deviceId;
        private int channelId;
        private RadioChannelInfo channelInfo;
        private bool isReadOnly;
        private DataBrokerClient broker;

        public RadioChannelDialog(int deviceId, int channelId)
        {
            InitializeComponent();
            this.deviceId = deviceId;
            this.channelId = channelId;
            this.isReadOnly = false;

            broker = new DataBrokerClient();
            broker.Subscribe(deviceId, "Channels", OnChannelsChanged);
            LoadChannel();
        }

        public RadioChannelDialog(RadioChannelInfo info)
        {
            InitializeComponent();
            this.channelInfo = info;
            this.isReadOnly = true;
            OkButton.IsEnabled = false;
            PopulateFromInfo(info);
        }

        private void OnChannelsChanged(int deviceId, string name, object data)
        {
            // Reload channel data
        }

        private void LoadChannel()
        {
            var channels = DataBroker.GetValue<RadioChannelInfo[]>(deviceId, "Channels");
            if (channels != null && channelId < channels.Length)
            {
                PopulateFromInfo(channels[channelId]);
            }
        }

        private void PopulateFromInfo(RadioChannelInfo info)
        {
            if (info == null) return;
            FrequencyBox.Text = (info.rx_freq / 1000000.0).ToString("F4");
            ChannelNameBox.Text = info.name_str ?? "";
            // TODO: Set Mode, Bandwidth, checkboxes from info
        }

        private void AdvancedButton_Click(object sender, RoutedEventArgs e)
        {
            AdvancedPanel.IsVisible = !AdvancedPanel.IsVisible;
            AdvancedButton.Content = AdvancedPanel.IsVisible ? "Basic" : "Advanced";
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Validate and save channel changes via DataBroker
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
