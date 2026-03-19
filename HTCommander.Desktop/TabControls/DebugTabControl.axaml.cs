/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public partial class DebugTabControl : UserControl
    {
        private DataBrokerClient broker;
        private const int MaxLogLength = 200000;

        public DebugTabControl()
        {
            InitializeComponent();
            broker = new DataBrokerClient();

            broker.Subscribe(1, new[] { "LogInfo", "LogError" }, OnLogMessage);
            broker.Subscribe(0, "BluetoothFramesDebug", OnBluetoothFramesDebugChanged);
            broker.Subscribe(1, "LoopbackMode", OnLoopbackModeChanged);
        }

        private void OnLogMessage(int deviceId, string name, object data)
        {
            if (data is string msg)
            {
                Dispatcher.UIThread.Post(() => AppendLog(msg, name == "LogError"));
            }
        }

        private void OnBluetoothFramesDebugChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                ShowBtFrames.IsChecked = data is bool b && b;
            });
        }

        private void OnLoopbackModeChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                LoopbackCheck.IsChecked = data is bool b && b;
            });
        }

        private void AppendLog(string message, bool isError = false)
        {
            string timestamp = DateTime.Now.ToString("HH:mm:ss");
            string prefix = isError ? "ERR" : "INF";
            string line = $"[{timestamp}] [{prefix}] {message}\n";

            string current = DebugLog.Text ?? "";
            if (current.Length > MaxLogLength)
            {
                current = current.Substring(current.Length - MaxLogLength / 2);
            }
            DebugLog.Text = current + line;
            DebugLog.CaretIndex = DebugLog.Text.Length;
        }

        private void ClearButton_Click(object sender, RoutedEventArgs e)
        {
            DebugLog.Text = "";
        }

        private async void SaveButton_Click(object sender, RoutedEventArgs e)
        {
            var platform = Program.PlatformServices;
            if (platform?.FilePicker == null) return;

            string path = await platform.FilePicker.SaveFileAsync("Save Debug Log", "debug.txt",
                new[] { "Text Files|*.txt", "All Files|*.*" });
            if (path != null)
            {
                try
                {
                    System.IO.File.WriteAllText(path, DebugLog.Text ?? "");
                    AppendLog($"Log saved to {path}");
                }
                catch (Exception ex)
                {
                    AppendLog($"Failed to save: {ex.Message}", true);
                }
            }
        }

        private void ShowBtFrames_Click(object sender, RoutedEventArgs e)
        {
            DataBroker.Dispatch(0, "BluetoothFramesDebug", ShowBtFrames.IsChecked == true);
        }

        private void Loopback_Click(object sender, RoutedEventArgs e)
        {
            DataBroker.Dispatch(1, "LoopbackMode", LoopbackCheck.IsChecked == true);
        }
    }
}
