using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class EditIdentSettingsDialog : Window
    {
        public string IdentText => IdentTextBox.Text?.Trim();
        public int Interval => (int)(IntervalUpDown.Value ?? 600);
        public bool IdentEnabled => EnabledCheck.IsChecked == true;
        public bool Confirmed { get; private set; }

        public EditIdentSettingsDialog()
        {
            InitializeComponent();
        }

        public void SetValues(string identText, int interval, bool enabled)
        {
            IdentTextBox.Text = identText;
            IntervalUpDown.Value = interval;
            EnabledCheck.IsChecked = enabled;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(IdentTextBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
