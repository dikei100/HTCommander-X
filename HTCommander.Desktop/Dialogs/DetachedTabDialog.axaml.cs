using System;
using Avalonia.Controls;

namespace HTCommander.Desktop.Dialogs
{
    public partial class DetachedTabDialog : Window
    {
        public Control TabContent
        {
            get => TabContentHost.Content as Control;
            set => TabContentHost.Content = value;
        }

        public DetachedTabDialog()
        {
            InitializeComponent();
        }

        public DetachedTabDialog(string title, Control content) : this()
        {
            Title = title;
            TabContentHost.Content = content;
        }

        protected override void OnClosed(EventArgs e)
        {
            TabContentHost.Content = null;
            base.OnClosed(e);
        }
    }
}
