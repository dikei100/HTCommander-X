using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AprsSmsDialog : Window
    {
        public string Destination => DestinationBox.Text?.Trim().ToUpper();
        public string Message => MessageBox.Text?.Trim();
        public bool Confirmed { get; private set; }

        public AprsSmsDialog()
        {
            InitializeComponent();
        }

        private void SendButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(DestinationBox.Text)) return;
            if (string.IsNullOrWhiteSpace(MessageBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
