/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Represents a compatible radio device found during Bluetooth scanning.
    /// </summary>
    public class CompatibleDevice
    {
        public string name;
        public string mac;
        public CompatibleDevice(string name, string mac) { this.name = name; this.mac = mac; }
    }
}
