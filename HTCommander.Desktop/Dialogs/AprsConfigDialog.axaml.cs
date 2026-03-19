using System;
using System.Globalization;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AprsConfigDialog : Window
    {
        public int SelectedChannelId { get; private set; } = -1;
        public float Frequency { get; private set; }
        public bool Confirmed { get; private set; }

        public AprsConfigDialog()
        {
            InitializeComponent();
        }

        public void SetChannels(RadioChannelInfo[] channels)
        {
            if (channels == null) return;
            for (int i = 0; i < channels.Length; i++)
            {
                if (channels[i] != null && !string.IsNullOrEmpty(channels[i].name_str))
                {
                    ChannelCombo.Items.Add(new ComboBoxItem
                    {
                        Content = $"{i}: {channels[i].name_str}",
                        Tag = i
                    });
                }
            }
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (ChannelCombo.SelectedItem is ComboBoxItem item)
            {
                SelectedChannelId = (int)item.Tag;
            }

            if (float.TryParse(FrequencyBox.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out float freq))
            {
                Frequency = freq;
            }

            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
