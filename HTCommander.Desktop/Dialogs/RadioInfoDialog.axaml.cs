using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioInfoDialog : Window
    {
        private DataBrokerClient broker;
        private int deviceId;

        public RadioInfoDialog()
        {
            InitializeComponent();
        }

        public RadioInfoDialog(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;

            broker = new DataBrokerClient();
            broker.Subscribe(deviceId, "Info", OnInfoChanged);

            LoadInfo();
        }

        private void LoadInfo()
        {
            var info = DataBroker.GetValue<RadioDevInfo>(deviceId, "Info");
            if (info != null) DisplayInfo(info);
        }

        private void OnInfoChanged(int deviceId, string name, object data)
        {
            if (data is RadioDevInfo info)
            {
                Dispatcher.UIThread.Post(() => DisplayInfo(info));
            }
        }

        private void DisplayInfo(RadioDevInfo info)
        {
            InfoPanel.Children.Clear();
            AddField("Vendor ID", $"0x{info.vendor_id:X4}");
            AddField("Product ID", $"0x{info.product_id:X4}");
            AddField("Hardware Version", info.hw_ver.ToString());
            AddField("Software Version", info.soft_ver.ToString());
            AddField("Channels", info.channel_count.ToString());
            AddField("Regions", info.region_count.ToString());
            AddField("Support Radio", info.support_radio ? "Yes" : "No");
            AddField("Support VFO", info.support_vfo ? "Yes" : "No");
            AddField("Support DMR", info.support_dmr ? "Yes" : "No");
            AddField("Support NOAA", info.support_noaa ? "Yes" : "No");
            AddField("GMRS", info.gmrs ? "Yes" : "No");
        }

        private void AddField(string label, string value)
        {
            var sp = new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8 };
            sp.Children.Add(new TextBlock { Text = label + ":", FontWeight = Avalonia.Media.FontWeight.SemiBold, Width = 130 });
            sp.Children.Add(new TextBlock { Text = value });
            InfoPanel.Children.Add(sp);
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
