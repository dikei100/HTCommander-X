using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class VoiceDetailsDialog : Window
    {
        public VoiceDetailsDialog()
        {
            InitializeComponent();
        }

        public void SetDetails(string time, string channel, string encoding, string source, string destination, string text)
        {
            TimeText.Text = time;
            ChannelText.Text = channel;
            EncodingText.Text = encoding;
            SourceText.Text = source;
            DestinationText.Text = destination;
            MessageText.Text = text;
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
