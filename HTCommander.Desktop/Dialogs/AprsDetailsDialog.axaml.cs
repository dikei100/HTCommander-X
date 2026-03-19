using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AprsDetailsDialog : Window
    {
        public AprsDetailsDialog()
        {
            InitializeComponent();
        }

        public void SetDetails(string source, string destination, string path, string info, string raw)
        {
            DetailsPanel.Children.Clear();
            AddField("Source", source);
            AddField("Destination", destination);
            AddField("Path", path);
            AddField("Info", info);
            AddField("Raw", raw);
        }

        private void AddField(string label, string value)
        {
            if (string.IsNullOrEmpty(value)) return;
            var sp = new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8 };
            sp.Children.Add(new TextBlock { Text = label + ":", FontWeight = Avalonia.Media.FontWeight.SemiBold, Width = 100 });
            sp.Children.Add(new TextBlock { Text = value, TextWrapping = Avalonia.Media.TextWrapping.Wrap });
            DetailsPanel.Children.Add(sp);
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
