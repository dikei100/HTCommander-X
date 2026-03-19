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
    /// Platform-agnostic audio playback and capture service.
    /// Windows: NAudio/WASAPI, Linux: PortAudio, Android: AudioTrack/AudioRecord.
    /// </summary>
    public interface IAudioService : IDisposable
    {
        /// <summary>
        /// Request audio/microphone permissions. No-op on desktop, critical on Android.
        /// </summary>
        Task<bool> RequestPermissionsAsync();

        /// <summary>
        /// Create an audio output (playback) instance.
        /// </summary>
        IAudioOutput CreateOutput(int sampleRate, int bitsPerSample, int channels);

        /// <summary>
        /// Create an audio input (capture) instance.
        /// </summary>
        IAudioInput CreateInput(int sampleRate, int bitsPerSample, int channels);

        /// <summary>
        /// Get available audio output device names.
        /// </summary>
        string[] GetOutputDevices();

        /// <summary>
        /// Get available audio input device names.
        /// </summary>
        string[] GetInputDevices();

        /// <summary>
        /// Release audio focus (Android lifecycle). No-op on desktop.
        /// </summary>
        void OnPause();

        /// <summary>
        /// Reclaim audio focus (Android lifecycle). No-op on desktop.
        /// </summary>
        void OnResume();
    }

    /// <summary>
    /// Audio output (playback) abstraction.
    /// </summary>
    public interface IAudioOutput : IDisposable
    {
        void Init(int sampleRate, int bitsPerSample, int channels);
        void Play();
        void Stop();
        void AddSamples(byte[] buffer, int offset, int count);
        float Volume { get; set; }
        string DeviceId { get; set; }
    }

    /// <summary>
    /// Audio input (capture) abstraction.
    /// </summary>
    public interface IAudioInput : IDisposable
    {
        void Start();
        void Stop();
        string DeviceId { get; set; }
        event Action<byte[], int> DataAvailable;
    }
}
