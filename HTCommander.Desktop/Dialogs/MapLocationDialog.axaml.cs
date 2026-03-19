using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class MapLocationDialog : Window
    {
        public string Latitude => LatitudeBox.Text?.Trim();
        public string Longitude => LongitudeBox.Text?.Trim();
        public string LocationName => LocationNameBox.Text?.Trim();
        public bool Confirmed { get; private set; }

        public MapLocationDialog()
        {
            InitializeComponent();
        }

        public void SetValues(string latitude, string longitude, string name)
        {
            LatitudeBox.Text = latitude;
            LongitudeBox.Text = longitude;
            LocationNameBox.Text = name;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(LatitudeBox.Text)) return;
            if (string.IsNullOrWhiteSpace(LongitudeBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
