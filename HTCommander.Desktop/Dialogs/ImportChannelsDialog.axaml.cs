using System;
using System.Collections.Generic;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class ImportChannelsDialog : Window
    {
        public string FilePath => FilePathBox.Text;
        public bool Confirmed { get; private set; }

        public ImportChannelsDialog()
        {
            InitializeComponent();
        }

        private async void BrowseButton_Click(object sender, RoutedEventArgs e)
        {
            var platform = Program.PlatformServices;
            if (platform?.FilePicker == null) return;

            string path = await platform.FilePicker.PickFileAsync("Select CSV File",
                new[] { "CSV Files|*.csv", "All Files|*.*" });
            if (!string.IsNullOrEmpty(path))
            {
                FilePathBox.Text = path;
                LoadPreview(path);
            }
        }

        private void LoadPreview(string path)
        {
            try
            {
                var lines = File.ReadAllLines(path);
                if (lines.Length == 0) return;

                var rows = new List<Dictionary<string, string>>();
                var headers = lines[0].Split(',');

                for (int i = 1; i < lines.Length && i <= 50; i++)
                {
                    var values = lines[i].Split(',');
                    var row = new Dictionary<string, string>();
                    for (int j = 0; j < headers.Length && j < values.Length; j++)
                    {
                        row[headers[j].Trim()] = values[j].Trim();
                    }
                    rows.Add(row);
                }

                PreviewGrid.ItemsSource = rows;
            }
            catch (Exception) { }
        }

        private void ImportButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(FilePathBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
