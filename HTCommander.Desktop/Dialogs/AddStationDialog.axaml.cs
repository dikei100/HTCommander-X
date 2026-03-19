using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AddStationDialog : Window
    {
        public string Callsign => CallsignBox.Text?.Trim().ToUpper();
        public string StationName => NameBox.Text?.Trim();
        public int StationType => TypeCombo.SelectedIndex;
        public string Description => DescriptionBox.Text?.Trim();
        public bool Confirmed { get; private set; }

        public AddStationDialog()
        {
            InitializeComponent();
        }

        public void SetStation(string callsign, string name, int type, string description)
        {
            CallsignBox.Text = callsign;
            NameBox.Text = name;
            TypeCombo.SelectedIndex = type;
            DescriptionBox.Text = description;
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrWhiteSpace(CallsignBox.Text)) return;
            Confirmed = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
