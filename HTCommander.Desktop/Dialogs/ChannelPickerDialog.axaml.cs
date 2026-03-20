using System;
using System.Collections.Generic;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using HamLib;

namespace HTCommander.Desktop.Dialogs
{
    public class ChannelPickerItem
    {
        public string Slot { get; set; }
        public string Name { get; set; }
        public string Frequency { get; set; }
        public IBrush Background { get; set; }
        public IBrush NameColor { get; set; }
        public int ChannelIndex { get; set; }
    }

    public partial class ChannelPickerDialog : Window
    {
        public int SelectedChannelIndex { get; private set; } = -1;
        public bool Confirmed { get; private set; }

        private List<ChannelPickerItem> allItems;
        private int currentIndex;

        public ChannelPickerDialog()
        {
            InitializeComponent();
        }

        public ChannelPickerDialog(string vfoLabel, RadioChannelInfo[] channels, int currentIndex)
        {
            InitializeComponent();
            this.currentIndex = currentIndex;
            TitleText.Text = $"Select a channel for VFO {vfoLabel}:";
            Title = $"Select Channel - VFO {vfoLabel}";

            allItems = new List<ChannelPickerItem>();
            for (int i = 0; i < channels.Length; i++)
            {
                var ch = channels[i];
                if (ch == null) continue;
                if (string.IsNullOrEmpty(ch.name_str) && ch.rx_freq == 0) continue;

                bool isCurrent = (i == currentIndex);
                allItems.Add(new ChannelPickerItem
                {
                    Slot = (i + 1).ToString(),
                    Name = !string.IsNullOrEmpty(ch.name_str) ? ch.name_str : $"CH {i + 1}",
                    Frequency = FormatFrequency(ch.rx_freq),
                    Background = isCurrent ? new SolidColorBrush(Color.Parse("#334FC3F7")) : Brushes.Transparent,
                    NameColor = isCurrent ? new SolidColorBrush(Color.Parse("#4FC3F7")) : Brushes.White,
                    ChannelIndex = i
                });
            }

            ChannelListBox.ItemsSource = allItems;

            // Select current channel
            var currentItem = allItems.FirstOrDefault(x => x.ChannelIndex == currentIndex);
            if (currentItem != null) ChannelListBox.SelectedItem = currentItem;

            FilterBox.TextChanged += FilterBox_TextChanged;
        }

        private void FilterBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            string filter = FilterBox.Text?.Trim() ?? "";
            if (string.IsNullOrEmpty(filter))
            {
                ChannelListBox.ItemsSource = allItems;
                return;
            }

            var filtered = allItems.Where(item =>
                item.Name.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                item.Frequency.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                item.Slot.Contains(filter, StringComparison.OrdinalIgnoreCase)
            ).ToList();

            ChannelListBox.ItemsSource = filtered;
        }

        private void ChannelListBox_DoubleTapped(object sender, Avalonia.Input.TappedEventArgs e)
        {
            if (ChannelListBox.SelectedItem is ChannelPickerItem item)
            {
                SelectedChannelIndex = item.ChannelIndex;
                Confirmed = true;
                Close();
            }
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (ChannelListBox.SelectedItem is ChannelPickerItem item)
            {
                SelectedChannelIndex = item.ChannelIndex;
                Confirmed = true;
            }
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();

        private static string FormatFrequency(int freq)
        {
            if (freq <= 0) return "--- .--- MHz";
            double mhz = freq / 1000000.0;
            return $"{mhz:F5} MHz";
        }
    }
}
