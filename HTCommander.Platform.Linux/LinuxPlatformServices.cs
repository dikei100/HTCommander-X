/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux platform service provider. Creates Linux-specific implementations
    /// of all platform abstractions.
    /// </summary>
    public class LinuxPlatformServices : IPlatformServices
    {
        public ISettingsStore Settings { get; }
        public IAudioService Audio { get; }
        public ISpeechService Speech { get; }
        public IFilePickerService FilePicker { get; }
        public IPlatformUtils PlatformUtils { get; }

        public LinuxPlatformServices()
        {
            Settings = new JsonFileSettingsStore();
            Audio = new LinuxAudioService();
            Speech = new LinuxSpeechService();
            FilePicker = new LinuxFilePickerService();
            PlatformUtils = new LinuxPlatformUtils();
        }

        public IRadioBluetooth CreateRadioBluetooth(IRadioHost radioHost)
        {
            return new LinuxRadioBluetooth(radioHost);
        }

        public IRadioAudioTransport CreateRadioAudioTransport()
        {
            return new LinuxRadioAudioTransport();
        }
    }
}
