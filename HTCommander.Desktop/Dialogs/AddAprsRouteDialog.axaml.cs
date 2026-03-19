using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AddAprsRouteDialog : Window
    {
        public string RouteName => RouteNameBox.Text?.Trim();
        public string RoutePath => RoutePathBox.Text?.Trim();
        public bool Confirmed { get; private set; }

        public AddAprsRouteDialog()
        {
            InitializeComponent();
        }

        public void SetValues(string name, string path)
        {
            RouteNameBox.Text = name;
            RoutePathBox.Text = path;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(RouteNameBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
