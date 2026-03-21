/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.IO;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux platform utilities using xdg-open and standard Linux paths.
    /// </summary>
    public class LinuxPlatformUtils : IPlatformUtils
    {
        public void OpenUrl(string url)
        {
            // Validate URL to prevent passing arbitrary arguments to xdg-open
            if (string.IsNullOrEmpty(url) || !Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
                (uri.Scheme != "http" && uri.Scheme != "https")) return;
            try
            {
                var psi = new ProcessStartInfo("xdg-open") { UseShellExecute = false };
                psi.ArgumentList.Add(url);
                Process.Start(psi);
            }
            catch (Exception) { }
        }

        public void OpenFileManager(string path)
        {
            if (string.IsNullOrEmpty(path)) return;
            try
            {
                var psi = new ProcessStartInfo("xdg-open") { UseShellExecute = false };
                psi.ArgumentList.Add(path);
                Process.Start(psi);
            }
            catch (Exception) { }
        }

        public void OpenBluetoothSettings()
        {
            // Try common Bluetooth settings tools
            try { Process.Start(new ProcessStartInfo("blueman-manager") { UseShellExecute = false }); return; }
            catch (Exception) { }
            try
            {
                var psi = new ProcessStartInfo("xdg-open") { UseShellExecute = false };
                psi.ArgumentList.Add("gnome-bluetooth-panel");
                Process.Start(psi);
            }
            catch (Exception) { }
        }

        public void BringWindowToFront()
        {
            // Handled by Avalonia window activation — no-op here
        }

        public string GetAppDataFolder()
        {
            string configDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "HTCommander");
            Directory.CreateDirectory(configDir);
            return configDir;
        }
    }
}
