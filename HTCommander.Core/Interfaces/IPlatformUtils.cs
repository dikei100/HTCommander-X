/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Platform-specific utilities (open URLs, file manager, BT settings, etc.).
    /// </summary>
    public interface IPlatformUtils
    {
        void OpenUrl(string url);
        void OpenFileManager(string path);
        void OpenBluetoothSettings();
        void BringWindowToFront();
        string GetAppDataFolder();
    }
}
