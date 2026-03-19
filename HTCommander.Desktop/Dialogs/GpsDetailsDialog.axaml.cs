using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;
using HTCommander.radio;

namespace HTCommander.Desktop.Dialogs
{
    public partial class GpsDetailsDialog : Window
    {
        private DataBrokerClient broker;
        private int deviceId;

        public GpsDetailsDialog()
        {
            InitializeComponent();
        }

        public GpsDetailsDialog(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;

            broker = new DataBrokerClient();
            broker.Subscribe(deviceId, "Position", OnPositionChanged);
            LoadPosition();
        }

        private void LoadPosition()
        {
            var pos = DataBroker.GetValue<RadioPosition>(deviceId, "Position");
            if (pos != null) DisplayPosition(pos);
            else AddField("Status", "No GPS position available");
        }

        private void OnPositionChanged(int deviceId, string name, object data)
        {
            if (data is RadioPosition pos)
            {
                Dispatcher.UIThread.Post(() => DisplayPosition(pos));
            }
        }

        private void DisplayPosition(RadioPosition pos)
        {
            InfoPanel.Children.Clear();
            AddField("Latitude", $"{pos.Latitude:F6}°");
            AddField("Longitude", $"{pos.Longitude:F6}°");
            AddField("Altitude", $"{pos.Altitude} m");
            AddField("Speed", $"{pos.Speed}");
            AddField("Heading", $"{pos.Heading}°");
            AddField("GPS Locked", pos.Locked ? "Yes" : "No");
            AddField("Time (UTC)", pos.TimeUTC.ToString("yyyy-MM-dd HH:mm:ss"));
        }

        private void AddField(string label, string value)
        {
            var sp = new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8 };
            sp.Children.Add(new TextBlock { Text = label + ":", FontWeight = Avalonia.Media.FontWeight.SemiBold, Width = 100 });
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
