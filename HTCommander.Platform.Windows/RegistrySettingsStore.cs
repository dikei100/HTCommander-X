/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using Microsoft.Win32;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows Registry-backed implementation of ISettingsStore.
    /// </summary>
    public class RegistrySettingsStore : ISettingsStore
    {
        private readonly string _applicationName;

        public RegistrySettingsStore(string applicationName)
        {
            if (string.IsNullOrEmpty(applicationName))
                throw new System.ArgumentException("Application name cannot be null or empty.", nameof(applicationName));
            _applicationName = applicationName;
            using (var key = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}")) { }
        }

        public void WriteString(string key, string value)
        {
            using (var regKey = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}"))
            {
                regKey?.SetValue(key, value, RegistryValueKind.String);
            }
        }

        public string ReadString(string key, string defaultValue)
        {
            using (var regKey = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}"))
            {
                if (regKey == null) return defaultValue;
                string r = regKey.GetValue(key) as string;
                return r ?? defaultValue;
            }
        }

        public void WriteInt(string key, int value)
        {
            using (var regKey = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}"))
            {
                regKey?.SetValue(key, value, RegistryValueKind.DWord);
            }
        }

        public int? ReadInt(string key, int? defaultValue)
        {
            using (var regKey = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}"))
            {
                if (regKey == null) return defaultValue;
                object value = regKey.GetValue(key);
                if (value is int intValue) return intValue;
                return defaultValue;
            }
        }

        public void WriteBool(string key, bool value)
        {
            using (var regKey = Registry.CurrentUser.CreateSubKey($"Software\\{_applicationName}"))
            {
                regKey?.SetValue(key, value ? 1 : 0, RegistryValueKind.DWord);
            }
        }

        public bool ReadBool(string key, bool defaultValue)
        {
            using (var regKey = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}"))
            {
                if (regKey == null) return defaultValue;
                object value = regKey.GetValue(key);
                if (value is int intValue) return intValue != 0;
                return defaultValue;
            }
        }

        public void DeleteValue(string key)
        {
            using (var regKey = Registry.CurrentUser.OpenSubKey($"Software\\{_applicationName}", writable: true))
            {
                regKey?.DeleteValue(key, throwOnMissingValue: false);
            }
        }
    }
}
