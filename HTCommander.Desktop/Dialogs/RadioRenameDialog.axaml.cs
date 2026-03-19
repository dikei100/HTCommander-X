using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioRenameDialog : Window
    {
        public string NewName => NameBox.Text?.Trim();
        public bool Confirmed { get; private set; }

        public RadioRenameDialog()
        {
            InitializeComponent();
        }

        public void SetCurrentName(string name)
        {
            NameBox.Text = name;
            NameBox.SelectAll();
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(NameBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
