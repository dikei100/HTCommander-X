using System;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class MailViewerDialog : Window
    {
        public bool ReplyRequested { get; private set; }
        public bool ForwardRequested { get; private set; }
        public bool DeleteRequested { get; private set; }

        public MailViewerDialog()
        {
            InitializeComponent();
        }

        public void SetMail(string from, string date, string subject, string body)
        {
            FromLabel.Text = $"From: {from}";
            DateLabel.Text = $"Date: {date}";
            SubjectLabel.Text = subject;
            BodyText.Text = body;
            Title = subject;
        }

        private void ReplyButton_Click(object sender, RoutedEventArgs e) { ReplyRequested = true; Close(); }
        private void ForwardButton_Click(object sender, RoutedEventArgs e) { ForwardRequested = true; Close(); }
        private void DeleteButton_Click(object sender, RoutedEventArgs e) { DeleteRequested = true; Close(); }
        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
