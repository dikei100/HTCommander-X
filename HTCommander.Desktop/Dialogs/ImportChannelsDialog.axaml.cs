using System;
using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public class ImportChannelEntry
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Frequency { get; set; }
        public string Mode { get; set; }
        public string Bandwidth { get; set; }
    }

    public partial class ImportChannelsDialog : Window
    {
        private int deviceId;
        private RadioChannelInfo[] channels;
        public bool Confirmed { get; private set; }

        public ImportChannelsDialog()
        {
            InitializeComponent();
        }

        public ImportChannelsDialog(int deviceId, RadioChannelInfo[] channels) : this()
        {
            this.deviceId = deviceId;
            this.channels = channels;

            InfoText.Text = $"{channels.Length} channels found. Click Import to write them to the radio.";
            ImportButton.IsEnabled = deviceId >= 0;
            if (deviceId < 0)
                InfoText.Text += "\nNo radio connected — connect a radio first.";

            var entries = new List<ImportChannelEntry>();
            for (int i = 0; i < channels.Length; i++)
            {
                var ch = channels[i];
                if (ch == null) continue;
                entries.Add(new ImportChannelEntry
                {
                    Id = (ch.channel_id + 1).ToString(),
                    Name = ch.name_str ?? "",
                    Frequency = (ch.rx_freq / 1000000.0).ToString("F4") + " MHz",
                    Mode = ch.rx_mod.ToString(),
                    Bandwidth = ch.bandwidth.ToString()
                });
            }
            PreviewGrid.ItemsSource = entries;
        }

        private void ImportButton_Click(object sender, RoutedEventArgs e)
        {
            if (deviceId < 0 || channels == null) return;

            // Write each channel to the radio
            foreach (var ch in channels)
            {
                if (ch == null) continue;
                DataBroker.Dispatch(deviceId, "WriteChannel", ch, store: false);
            }

            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
