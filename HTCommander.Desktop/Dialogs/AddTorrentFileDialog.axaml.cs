using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AddTorrentFileDialog : Window
    {
        public string Filename => FilenameBox.Text?.Trim();
        public string Description => DescriptionBox.Text?.Trim();
        public int Mode => ModeCombo.SelectedIndex;
        public bool Confirmed { get; private set; }

        public AddTorrentFileDialog()
        {
            InitializeComponent();
        }

        private async void BrowseButton_Click(object sender, RoutedEventArgs e)
        {
            var storage = StorageProvider;
            if (storage == null) return;
            var result = await storage.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Select File",
                AllowMultiple = false
            });
            if (result != null && result.Count > 0)
            {
                FilenameBox.Text = result[0].Path.LocalPath;
            }
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(FilenameBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
