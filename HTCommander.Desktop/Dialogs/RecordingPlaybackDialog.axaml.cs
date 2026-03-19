using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RecordingPlaybackDialog : Window
    {
        public string RecordingPath { get; set; }
        private bool isPlaying;

        public RecordingPlaybackDialog()
        {
            InitializeComponent();
        }

        public void SetRecording(string path)
        {
            RecordingPath = path;
            StatusText.Text = $"Ready: {System.IO.Path.GetFileName(path)}";
        }

        public void UpdateProgress(double percent)
        {
            PlaybackProgress.Value = percent;
            if (percent >= 100) StopPlayback();
        }

        private void PlayButton_Click(object sender, RoutedEventArgs e)
        {
            if (isPlaying) return;
            isPlaying = true;
            PlayButton.IsEnabled = false;
            StopButton.IsEnabled = true;
            StatusText.Text = "Playing...";
        }

        private void StopButton_Click(object sender, RoutedEventArgs e)
        {
            StopPlayback();
        }

        private void StopPlayback()
        {
            isPlaying = false;
            PlayButton.IsEnabled = true;
            StopButton.IsEnabled = false;
            StatusText.Text = "Stopped";
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            if (isPlaying) StopPlayback();
            Close();
        }
    }
}
