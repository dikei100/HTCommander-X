using System;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class MailComposeDialog : Window
    {
        public string ToAddress => ToBox.Text;
        public string Subject => SubjectBox.Text;
        public string Body => BodyBox.Text;
        public bool Sent { get; private set; }
        public bool SavedAsDraft { get; private set; }

        public MailComposeDialog()
        {
            InitializeComponent();
        }

        public MailComposeDialog(string to, string subject, string body) : this()
        {
            ToBox.Text = to;
            SubjectBox.Text = subject;
            BodyBox.Text = body;
        }

        private void SendButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(ToBox.Text)) return;
            Sent = true;
            Close();
        }

        private void SaveDraftButton_Click(object sender, RoutedEventArgs e)
        {
            SavedAsDraft = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
