/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Platform-agnostic settings persistence.
    /// Windows: Registry, Linux/Android: JSON file.
    /// </summary>
    public interface ISettingsStore
    {
        void WriteString(string key, string value);
        string ReadString(string key, string defaultValue);
        void WriteInt(string key, int value);
        int? ReadInt(string key, int? defaultValue);
        void WriteBool(string key, bool value);
        bool ReadBool(string key, bool defaultValue);
        void DeleteValue(string key);
    }
}
