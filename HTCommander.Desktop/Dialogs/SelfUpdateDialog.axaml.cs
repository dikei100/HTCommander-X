using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class SelfUpdateDialog : Window
    {
        public bool UpdateRequested { get; private set; }

        public SelfUpdateDialog()
        {
            InitializeComponent();
        }

        public void SetVersionInfo(string currentVersion, string newVersion)
        {
            VersionInfo.Text = $"A new version ({newVersion}) is available. You are running {currentVersion}.";
        }

        private void UpdateButton_Click(object sender, RoutedEventArgs e)
        {
            UpdateRequested = true;
            StatusText.Text = "Update will be applied on next restart.";
            UpdateButton.IsEnabled = false;
        }

        private void LaterButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
