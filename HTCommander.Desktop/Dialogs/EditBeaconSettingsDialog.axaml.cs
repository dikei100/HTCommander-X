using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class EditBeaconSettingsDialog : Window
    {
        public string BeaconText => BeaconTextBox.Text?.Trim();
        public int Interval => (int)(IntervalUpDown.Value ?? 60);
        public bool BeaconEnabled => EnabledCheck.IsChecked == true;
        public bool Confirmed { get; private set; }

        public EditBeaconSettingsDialog()
        {
            InitializeComponent();
        }

        public void SetValues(string beaconText, int interval, bool enabled)
        {
            BeaconTextBox.Text = beaconText;
            IntervalUpDown.Value = interval;
            EnabledCheck.IsChecked = enabled;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(BeaconTextBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
