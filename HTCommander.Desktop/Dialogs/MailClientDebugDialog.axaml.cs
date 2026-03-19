using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class MailClientDebugDialog : Window
    {
        private DataBrokerClient broker;

        public MailClientDebugDialog()
        {
            InitializeComponent();

            broker = new DataBrokerClient();
            broker.Subscribe(1, "WinlinkStateMessage", OnLogMessage);
        }

        private void OnLogMessage(int deviceId, string name, object data)
        {
            if (data is string msg)
            {
                Dispatcher.UIThread.Post(() => AppendLog(msg));
            }
        }

        public void AppendLog(string message)
        {
            LogBox.Text += message + Environment.NewLine;
            LogBox.CaretIndex = LogBox.Text?.Length ?? 0;
        }

        private void ClearButton_Click(object sender, RoutedEventArgs e)
        {
            LogBox.Text = string.Empty;
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
