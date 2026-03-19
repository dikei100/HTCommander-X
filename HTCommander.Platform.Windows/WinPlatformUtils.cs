/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows platform utilities.
    /// </summary>
    public class WinPlatformUtils : IPlatformUtils
    {
        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        public void OpenUrl(string url)
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }

        public void OpenFileManager(string path)
        {
            Process.Start("explorer.exe", path);
        }

        public void OpenBluetoothSettings()
        {
            Process.Start(new ProcessStartInfo("ms-settings:bluetooth") { UseShellExecute = true });
        }

        public void BringWindowToFront()
        {
            var proc = Process.GetCurrentProcess();
            SetForegroundWindow(proc.MainWindowHandle);
        }

        public string GetAppDataFolder()
        {
            return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        }
    }
}
