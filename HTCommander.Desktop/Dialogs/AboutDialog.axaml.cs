using System;
using System.Diagnostics;
using System.Reflection;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AboutDialog : Window
    {
        public AboutDialog()
        {
            InitializeComponent();
            var version = Assembly.GetEntryAssembly()?.GetName().Version;
            VersionText.Text = $"Version: {version?.ToString() ?? "unknown"}";
        }

        private void GithubLink_Click(object sender, RoutedEventArgs e)
        {
            Program.PlatformServices?.PlatformUtils?.OpenUrl("https://github.com/dikei100/HTCommander-X");
        }

        private void LicenseLink_Click(object sender, RoutedEventArgs e)
        {
            Program.PlatformServices?.PlatformUtils?.OpenUrl("https://www.apache.org/licenses/LICENSE-2.0");
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
