/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Windows Registry-backed implementation of ISettingsStore.
    /// Wraps the existing RegistryHelper for backward compatibility.
    /// </summary>
    public class RegistrySettingsStore : ISettingsStore
    {
        private readonly RegistryHelper _registryHelper;

        public RegistrySettingsStore(string applicationName)
        {
            _registryHelper = new RegistryHelper(applicationName);
        }

        public void WriteString(string key, string value) => _registryHelper.WriteString(key, value);
        public string ReadString(string key, string defaultValue) => _registryHelper.ReadString(key, defaultValue);
        public void WriteInt(string key, int value) => _registryHelper.WriteInt(key, value);
        public int? ReadInt(string key, int? defaultValue) => _registryHelper.ReadInt(key, defaultValue);
        public void WriteBool(string key, bool value) => _registryHelper.WriteBool(key, value);
        public bool ReadBool(string key, bool defaultValue) => _registryHelper.ReadBool(key, defaultValue);
        public void DeleteValue(string key) => _registryHelper.DeleteValue(key);
    }
}
