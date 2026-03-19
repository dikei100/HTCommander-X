using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;

namespace HTCommander.Desktop.Dialogs
{
    public partial class ImagePreviewDialog : Window
    {
        private Bitmap _bitmap;

        public ImagePreviewDialog()
        {
            InitializeComponent();
        }

        public void SetImage(Bitmap bitmap, string title = null)
        {
            _bitmap = bitmap;
            PreviewImage.Source = bitmap;
            if (title != null) Title = title;
        }

        public void SetImageFromFile(string path)
        {
            try
            {
                _bitmap = new Bitmap(path);
                PreviewImage.Source = _bitmap;
                Title = System.IO.Path.GetFileName(path);
            }
            catch (Exception) { }
        }

        private async void SaveButton_Click(object sender, RoutedEventArgs e)
        {
            if (_bitmap == null) return;
            var platform = Program.PlatformServices;
            if (platform?.FilePicker == null) return;

            string path = await platform.FilePicker.SaveFileAsync("Save Image", "image.png",
                new[] { "PNG Files|*.png", "All Files|*.*" });
            if (path != null)
            {
                try { _bitmap.Save(path); } catch (Exception) { }
            }
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
