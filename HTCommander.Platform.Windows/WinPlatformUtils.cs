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
            // Validate URL scheme to prevent command execution via shell
            if (!Uri.TryCreate(url, UriKind.Absolute, out Uri uri)) return;
            if (uri.Scheme != "http" && uri.Scheme != "https") return;
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        }

        public void OpenFileManager(string path)
        {
            // Use ArgumentList to prevent argument injection
            var psi = new ProcessStartInfo("explorer.exe") { UseShellExecute = false };
            psi.ArgumentList.Add(path);
            Process.Start(psi);
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
