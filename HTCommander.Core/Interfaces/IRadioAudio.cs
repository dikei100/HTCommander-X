/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Platform-agnostic interface for RadioAudio functionality.
    /// The concrete implementation (RadioAudio) lives in the platform-specific project
    /// because it depends on NAudio, WinRT Bluetooth, etc.
    /// </summary>
    public interface IRadioAudio : IDisposable
    {
        bool Recording { get; }
        bool IsAudioEnabled { get; }
        float Volume { get; set; }
        int currentChannelId { get; set; }
        string currentChannelName { get; set; }
        void Start();
        void Stop();
    }
}
