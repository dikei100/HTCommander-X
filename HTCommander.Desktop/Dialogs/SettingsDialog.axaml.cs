using System;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class SettingsDialog : Window
    {
        private DataBrokerClient broker;

        public SettingsDialog()
        {
            InitializeComponent();
            broker = new DataBrokerClient();
            LoadSettings();
        }

        private void LoadSettings()
        {
            CallSignBox.Text = DataBroker.GetValue<string>(0, "CallSign", "");
            AllowTransmitCheck.IsChecked = DataBroker.GetValue<bool>(0, "AllowTransmit", false);
            CheckUpdatesCheck.IsChecked = DataBroker.GetValue<bool>(0, "CheckForUpdates", false);

            // Populate station IDs 0-15
            for (int i = 0; i <= 15; i++) StationIdCombo.Items.Add(i.ToString());
            int stationId = DataBroker.GetValue<int>(0, "StationId", 0);
            StationIdCombo.SelectedIndex = Math.Min(stationId, 15);

            // Audio devices
            var audio = Program.PlatformServices?.Audio;
            if (audio != null)
            {
                foreach (var dev in audio.GetOutputDevices()) OutputDeviceCombo.Items.Add(dev);
                foreach (var dev in audio.GetInputDevices()) InputDeviceCombo.Items.Add(dev);
            }

            // Voice
            var speech = Program.PlatformServices?.Speech;
            if (speech != null && speech.IsAvailable)
            {
                foreach (var voice in speech.GetVoices()) VoiceCombo.Items.Add(voice);
            }

            // Server settings
            WebServerCheck.IsChecked = DataBroker.GetValue<bool>(0, "WebServerEnabled", false);
            WebPortUpDown.Value = DataBroker.GetValue<int>(0, "WebServerPort", 8080);
            AgwpeServerCheck.IsChecked = DataBroker.GetValue<bool>(0, "AgwpeServerEnabled", false);
            AgwpePortUpDown.Value = DataBroker.GetValue<int>(0, "AgwpeServerPort", 8000);

            // Winlink
            WinlinkPasswordBox.Text = DataBroker.GetValue<string>(0, "WinlinkPassword", "");
            WinlinkUseStationIdCheck.IsChecked = DataBroker.GetValue<bool>(0, "WinlinkUseStationId", false);
        }

        private void SaveSettings()
        {
            DataBroker.Dispatch(0, "CallSign", CallSignBox.Text ?? "");
            DataBroker.Dispatch(0, "StationId", StationIdCombo.SelectedIndex);
            DataBroker.Dispatch(0, "AllowTransmit", AllowTransmitCheck.IsChecked == true);
            DataBroker.Dispatch(0, "CheckForUpdates", CheckUpdatesCheck.IsChecked == true);

            DataBroker.Dispatch(0, "WebServerEnabled", WebServerCheck.IsChecked == true);
            DataBroker.Dispatch(0, "WebServerPort", (int)(WebPortUpDown.Value ?? 8080));
            DataBroker.Dispatch(0, "AgwpeServerEnabled", AgwpeServerCheck.IsChecked == true);
            DataBroker.Dispatch(0, "AgwpeServerPort", (int)(AgwpePortUpDown.Value ?? 8000));

            DataBroker.Dispatch(0, "WinlinkPassword", WinlinkPasswordBox.Text ?? "");
            DataBroker.Dispatch(0, "WinlinkUseStationId", WinlinkUseStationIdCheck.IsChecked == true);
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            SaveSettings();
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();

        private void AddRoute_Click(object sender, RoutedEventArgs e) { /* TODO */ }
        private void EditRoute_Click(object sender, RoutedEventArgs e) { /* TODO */ }
        private void DeleteRoute_Click(object sender, RoutedEventArgs e) { /* TODO */ }

        protected override void OnClosed(EventArgs e)
        {
            broker?.Dispose();
            base.OnClosed(e);
        }
    }
}
