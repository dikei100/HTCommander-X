using System;
using Avalonia.Controls;

namespace HTCommander.Desktop.Dialogs
{
    public partial class RadioFormDialog : Window
    {
        public int DeviceId { get; }

        public RadioFormDialog()
        {
            InitializeComponent();
        }

        public RadioFormDialog(int deviceId, string friendlyName = null) : this()
        {
            DeviceId = deviceId;
            if (!string.IsNullOrEmpty(friendlyName))
                Title = $"Radio Panel - {friendlyName}";
            else
                Title = $"Radio Panel - Device {deviceId}";
        }

        public void SetContent(Control content)
        {
            RadioPanelHost.Content = content;
        }

        protected override void OnClosed(EventArgs e)
        {
            RadioPanelHost.Content = null;
            base.OnClosed(e);
        }
    }
}
