using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class ActiveStationSelectorDialog : Window
    {
        public string SelectedStation => StationListBox.SelectedItem as string;
        public bool Confirmed { get; private set; }

        public ActiveStationSelectorDialog()
        {
            InitializeComponent();
        }

        public void SetStations(IEnumerable<string> stations)
        {
            StationListBox.ItemsSource = stations;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (StationListBox.SelectedItem == null) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
