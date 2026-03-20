/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Threading.Tasks;

namespace HTCommander
{
    /// <summary>
    /// Platform service provider — each platform registers its implementations.
    /// </summary>
    public interface IPlatformServices
    {
        ISettingsStore Settings { get; }
        IRadioBluetooth CreateRadioBluetooth(IRadioHost radioHost);
        IRadioAudioTransport CreateRadioAudioTransport();
        IAudioService Audio { get; }
        ISpeechService Speech { get; }
        IFilePickerService FilePicker { get; }
        IPlatformUtils PlatformUtils { get; }
        IVirtualSerialPort CreateVirtualSerialPort();
        IVirtualAudioProvider CreateVirtualAudioProvider();
    }
}
