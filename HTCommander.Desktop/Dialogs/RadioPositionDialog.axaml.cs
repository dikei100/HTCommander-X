using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioPositionDialog : Window
    {
        public string Latitude => LatitudeBox.Text?.Trim();
        public string Longitude => LongitudeBox.Text?.Trim();
        public string Altitude => AltitudeBox.Text?.Trim();
        public bool Confirmed { get; private set; }

        public RadioPositionDialog()
        {
            InitializeComponent();
        }

        public void SetValues(string latitude, string longitude, string altitude)
        {
            LatitudeBox.Text = latitude;
            LongitudeBox.Text = longitude;
            AltitudeBox.Text = altitude;
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
