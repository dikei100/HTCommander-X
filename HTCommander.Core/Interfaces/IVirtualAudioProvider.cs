/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Platform abstraction for virtual audio devices.
    /// Creates bidirectional audio routing for external ham radio software.
    /// </summary>
    public interface IVirtualAudioProvider : IDisposable
    {
        bool Create(int sampleRate);
        void Destroy();
        void WriteSamples(byte[] pcm, int offset, int count);
        event Action<byte[], int> TxDataAvailable;
        string SinkName { get; }
        string SourceName { get; }
        bool IsRunning { get; }
    }
}
