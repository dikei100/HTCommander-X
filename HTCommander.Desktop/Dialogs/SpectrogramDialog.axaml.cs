using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;

namespace HTCommander.Desktop.Dialogs
{
    public partial class SpectrogramDialog : Window
    {
        public SpectrogramDialog()
        {
            InitializeComponent();
        }

        public void SetImage(Bitmap bitmap)
        {
            SpectrogramImage.Source = bitmap;
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
