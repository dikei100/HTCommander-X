using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class MessageDialog : Window
    {
        public bool Confirmed { get; private set; }

        public MessageDialog()
        {
            InitializeComponent();
        }

        public MessageDialog(string message, string title = "Confirm")
        {
            InitializeComponent();
            Title = title;
            MessageText.Text = message;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
