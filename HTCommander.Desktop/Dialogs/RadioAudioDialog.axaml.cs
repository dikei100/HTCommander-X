using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioAudioDialog : Window
    {
        private DataBrokerClient broker;
        private int deviceId;

        public RadioAudioDialog(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;

            broker = new DataBrokerClient();
            broker.Subscribe(deviceId, new string[] { "AudioState", "SetOutputVolume", "SetMute" }, OnBrokerMessage);
        }

        private void OnBrokerMessage(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                switch (name)
                {
                    case "AudioState":
                        if (data is AudioStateInfo state)
                        {
                            VolumeSlider.Value = state.Volume;
                            MuteCheckBox.IsChecked = state.Muted;
                            StatusText.Text = state.Status ?? "Ready";
                            if (state.OutputDevices != null)
                            {
                                OutputDeviceBox.ItemsSource = state.OutputDevices;
                                if (state.SelectedOutputDevice != null)
                                    OutputDeviceBox.SelectedItem = state.SelectedOutputDevice;
                            }
                        }
                        break;
                    case "SetOutputVolume":
                        if (data is double vol) VolumeSlider.Value = vol;
                        break;
                    case "SetMute":
                        if (data is bool muted) MuteCheckBox.IsChecked = muted;
                        break;
                }
            });
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            broker.Dispatch(deviceId, "SetOutputVolume", VolumeSlider.Value, store: false);
            broker.Dispatch(deviceId, "SetMute", MuteCheckBox.IsChecked == true, store: false);
            if (OutputDeviceBox.SelectedItem != null)
            {
                broker.Dispatch(deviceId, "SetOutputDevice", OutputDeviceBox.SelectedItem.ToString(), store: false);
            }
            Close();
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }

    public class AudioStateInfo
    {
        public double Volume { get; set; }
        public bool Muted { get; set; }
        public string Status { get; set; }
        public string[] OutputDevices { get; set; }
        public string SelectedOutputDevice { get; set; }
    }
}
