/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Platform abstraction for virtual serial port (PTY on Linux, COM on Windows).
    /// Used by CatSerialServer for Kenwood TS-2000 CAT emulation.
    /// </summary>
    public interface IVirtualSerialPort : IDisposable
    {
        bool Create();
        string DevicePath { get; }
        event Action<byte[], int> DataReceived;
        void Write(byte[] data, int offset, int count);
        bool IsRunning { get; }
    }
}
