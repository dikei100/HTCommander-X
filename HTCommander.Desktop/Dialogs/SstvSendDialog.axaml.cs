using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;

namespace HTCommander.Desktop.Dialogs
{
    public partial class SstvSendDialog : Window
    {
        public string SelectedImagePath { get; private set; }
        public int SelectedMode => ModeCombo.SelectedIndex;
        public bool SendRequested { get; private set; }

        public SstvSendDialog()
        {
            InitializeComponent();
        }

        private async void SelectImage_Click(object sender, RoutedEventArgs e)
        {
            var platform = Program.PlatformServices;
            if (platform?.FilePicker == null) return;

            string path = await platform.FilePicker.PickFileAsync("Select Image",
                new[] { "Image Files|*.png;*.jpg;*.jpeg;*.bmp", "All Files|*.*" });

            if (path != null)
            {
                SelectedImagePath = path;
                ImagePath.Text = System.IO.Path.GetFileName(path);
                SendButton.IsEnabled = true;

                try
                {
                    PreviewImage.Source = new Bitmap(path);
                }
                catch (Exception) { }
            }
        }

        private void SendButton_Click(object sender, RoutedEventArgs e)
        {
            SendRequested = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
