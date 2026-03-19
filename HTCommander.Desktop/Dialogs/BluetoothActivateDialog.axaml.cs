using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class BluetoothActivateDialog : Window
    {
        public BluetoothActivateDialog()
        {
            InitializeComponent();
        }

        private void OpenSettings_Click(object sender, RoutedEventArgs e)
        {
            Program.PlatformServices?.PlatformUtils?.OpenBluetoothSettings();
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
