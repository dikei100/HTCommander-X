/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public partial class VoiceTabControl : UserControl
    {
        private DataBrokerClient broker;

        public VoiceTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(DataBroker.AllDevices, new[] { "ProcessingVoice", "TextReady", "VoiceTransmitStateChanged" }, OnVoiceEvent);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(1, "VoiceHandlerState", OnVoiceHandlerStateChanged);
            broker.Subscribe(0, "AllowTransmit", OnAllowTransmitChanged);
        }

        private void OnVoiceEvent(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                if (name == "TextReady" && data is string text)
                {
                    AddMessage(text, false);
                }
                else if (name == "VoiceTransmitStateChanged")
                {
                    VoiceStatus.Text = data?.ToString() ?? "Idle";
                }
            });
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update radio list */ });
        }

        private void OnVoiceHandlerStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => { /* Update handler state */ });
        }

        private void OnAllowTransmitChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                bool allow = data is bool b && b;
                TransmitButton.IsEnabled = allow;
            });
        }

        private void AddMessage(string text, bool outbound)
        {
            var border = new Border
            {
                Background = outbound ?
                    Avalonia.Media.Brushes.LightBlue :
                    Avalonia.Media.Brushes.WhiteSmoke,
                CornerRadius = new Avalonia.CornerRadius(4),
                Padding = new Avalonia.Thickness(8, 4),
                Margin = new Avalonia.Thickness(outbound ? 40 : 0, 0, outbound ? 0 : 40, 0)
            };

            var tb = new TextBlock
            {
                Text = text,
                TextWrapping = Avalonia.Media.TextWrapping.Wrap
            };
            border.Child = tb;
            VoiceMessages.Children.Add(border);
        }

        private void TransmitButton_Click(object sender, RoutedEventArgs e)
        {
            SendMessage();
        }

        private void VoiceInput_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                SendMessage();
                e.Handled = true;
            }
        }

        private void SendMessage()
        {
            string text = VoiceInput.Text?.Trim();
            if (string.IsNullOrEmpty(text)) return;

            AddMessage(text, true);
            VoiceInput.Text = "";
            // TODO: Dispatch voice message via DataBroker based on selected mode
        }

        private void RecordButton_Click(object sender, RoutedEventArgs e)
        {
            // TODO: Toggle recording state
        }
    }
}
