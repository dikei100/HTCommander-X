using System;
using System.Threading;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RecordingPlaybackDialog : Window
    {
        public string RecordingPath { get; set; }
        private bool isPlaying;
        private IAudioOutput audioOutput;
        private CancellationTokenSource playbackCts;
        private Task playbackTask;

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

        private async void PlayButton_Click(object sender, RoutedEventArgs e)
        {
            if (isPlaying || string.IsNullOrEmpty(RecordingPath)) return;
            isPlaying = true;
            PlayButton.IsEnabled = false;
            StopButton.IsEnabled = true;
            StatusText.Text = "Playing...";

            playbackCts = new CancellationTokenSource();
            var token = playbackCts.Token;

            playbackTask = Task.Run(() =>
            {
                try
                {
                    var (samples, wavParams) = HamLib.WavFile.Read(RecordingPath);

                    // Convert stereo to mono if needed
                    if (wavParams.NumChannels > 1)
                    {
                        int monoLen = samples.Length / wavParams.NumChannels;
                        short[] mono = new short[monoLen];
                        for (int i = 0; i < monoLen; i++)
                        {
                            int sum = 0;
                            for (int ch = 0; ch < wavParams.NumChannels; ch++)
                                sum += samples[i * wavParams.NumChannels + ch];
                            mono[i] = (short)(sum / wavParams.NumChannels);
                        }
                        samples = mono;
                    }

                    // Create audio output
                    var audio = Program.PlatformServices?.Audio;
                    if (audio == null) return;
                    audioOutput = audio.CreateOutput(wavParams.SampleRate, 16, 1);
                    if (audioOutput == null) return;
                    audioOutput.Play();

                    // Convert to bytes
                    byte[] pcmBytes = new byte[samples.Length * 2];
                    for (int i = 0; i < samples.Length; i++)
                    {
                        pcmBytes[i * 2] = (byte)(samples[i] & 0xFF);
                        pcmBytes[i * 2 + 1] = (byte)((samples[i] >> 8) & 0xFF);
                    }

                    int chunkSize = wavParams.SampleRate * 2 / 10; // 100ms chunks
                    int totalChunks = (pcmBytes.Length + chunkSize - 1) / chunkSize;

                    for (int c = 0; c < totalChunks; c++)
                    {
                        if (token.IsCancellationRequested) break;

                        int offset = c * chunkSize;
                        int len = Math.Min(chunkSize, pcmBytes.Length - offset);
                        audioOutput.AddSamples(pcmBytes, offset, len);

                        double pct = (c + 1) * 100.0 / totalChunks;
                        Dispatcher.UIThread.Post(() => UpdateProgress(pct));

                        Thread.Sleep(100);
                    }
                }
                catch (Exception) { }
                finally
                {
                    audioOutput?.Stop();
                    audioOutput?.Dispose();
                    audioOutput = null;
                    Dispatcher.UIThread.Post(() => StopPlayback());
                }
            }, token);
        }

        private void StopButton_Click(object sender, RoutedEventArgs e)
        {
            StopPlayback();
        }

        private void StopPlayback()
        {
            playbackCts?.Cancel();
            isPlaying = false;
            PlayButton.IsEnabled = true;
            StopButton.IsEnabled = false;
            StatusText.Text = "Stopped";
        }

        protected override void OnClosed(EventArgs e)
        {
            playbackCts?.Cancel();
            audioOutput?.Stop();
            audioOutput?.Dispose();
            base.OnClosed(e);
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            if (isPlaying) StopPlayback();
            Close();
        }
    }
}
