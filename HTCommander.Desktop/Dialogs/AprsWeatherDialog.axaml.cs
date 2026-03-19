using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class AprsWeatherDialog : Window
    {
        public AprsWeatherDialog()
        {
            InitializeComponent();
        }

        public void SetWeatherData(string station, string temperature, string humidity,
            string pressure, string windSpeed, string windDirection, string rainfall)
        {
            WeatherPanel.Children.Clear();
            AddField("Station", station);
            AddField("Temperature", temperature);
            AddField("Humidity", humidity);
            AddField("Pressure", pressure);
            AddField("Wind Speed", windSpeed);
            AddField("Wind Dir", windDirection);
            AddField("Rainfall", rainfall);
        }

        private void AddField(string label, string value)
        {
            if (string.IsNullOrEmpty(value)) return;
            var sp = new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8 };
            sp.Children.Add(new TextBlock { Text = label + ":", FontWeight = Avalonia.Media.FontWeight.SemiBold, Width = 100 });
            sp.Children.Add(new TextBlock { Text = value });
            WeatherPanel.Children.Add(sp);
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }
}
