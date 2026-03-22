/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Threading;

namespace HTCommander
{
    /// <summary>
    /// Bridges radio audio to/from virtual audio devices for external software.
    /// RX: Radio PCM (32kHz) → resample 48kHz → virtual audio source (external software input)
    /// TX: Virtual audio sink (external software output) → resample 32kHz → TransmitVoicePCM
    /// </summary>
    public class VirtualAudioBridge : IDisposable
    {
        private DataBrokerClient broker;
        private volatile IVirtualAudioProvider provider;
        private IPlatformServices platformServices;
        private volatile bool running = false;
        private int activeRadioId = -1;

        public VirtualAudioBridge(IPlatformServices platform)
        {
            platformServices = platform;
            broker = new DataBrokerClient();
            broker.Subscribe(0, "VirtualAudioEnabled", OnSettingChanged);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "AudioDataAvailable", OnAudioDataAvailable);

            int enabled = broker.GetValue<int>(0, "VirtualAudioEnabled", 0);
            if (enabled == 1)
            {
                Start();
            }
        }

        private void OnSettingChanged(int deviceId, string name, object data)
        {
            int enabled = broker.GetValue<int>(0, "VirtualAudioEnabled", 0);
            if (enabled == 1 && !running)
            {
                Start();
            }
            else if (enabled != 1 && running)
            {
                Stop();
            }
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            activeRadioId = GetFirstConnectedRadioId();
        }

        private void OnAudioDataAvailable(int deviceId, string name, object data)
        {
            if (!running || provider == null) return;
            if (deviceId < 100) return;

            try
            {
                // Only forward RX audio (Transmit == false)
                var transmitProp = data?.GetType().GetProperty("Transmit");
                if (transmitProp != null)
                {
                    object transmitVal = transmitProp.GetValue(data);
                    if (transmitVal is bool isTransmit && isTransmit) return;
                }

                var dataProp = data?.GetType().GetProperty("Data");
                var lengthProp = data?.GetType().GetProperty("Length");
                if (dataProp == null || lengthProp == null) return;

                byte[] pcm = dataProp.GetValue(data) as byte[];
                int length = 0;
                object lengthVal = lengthProp.GetValue(data);
                if (lengthVal is int l) length = l;

                if (pcm == null || length <= 0) return;

                // Resample 32kHz → 48kHz for PulseAudio
                byte[] input = pcm;
                if (length < pcm.Length)
                {
                    input = new byte[length];
                    Array.Copy(pcm, 0, input, 0, length);
                }
                byte[] resampled = AudioResampler.Resample16BitMono(input, 32000, 48000);
                provider.WriteSamples(resampled, 0, resampled.Length);
            }
            catch { }
        }

        private void OnTxDataAvailable(byte[] data, int length)
        {
            if (!running) return;
            int radioId = activeRadioId;
            if (radioId < 0) radioId = GetFirstConnectedRadioId();
            if (radioId < 0) return;

            // Only transmit if PTT is active (via rigctld or CAT)
            bool pttOn = false;
            var pttState = broker.GetValue<object>(1, "ExternalPttState", null);
            if (pttState is bool b) pttOn = b;
            if (!pttOn) return;

            try
            {
                // Resample 48kHz → 32kHz for radio
                byte[] input = data;
                if (length < data.Length)
                {
                    input = new byte[length];
                    Array.Copy(data, 0, input, 0, length);
                }
                byte[] resampled = AudioResampler.Resample16BitMono(input, 48000, 32000);
                broker.Dispatch(radioId, "TransmitVoicePCM", resampled, store: false);
            }
            catch { }
        }

        private void Start()
        {
            if (running) return;
            if (platformServices == null) return;

            provider = platformServices.CreateVirtualAudioProvider();
            if (provider == null)
            {
                Log("Virtual audio bridge: platform does not support virtual audio");
                return;
            }

            if (!provider.Create(48000))
            {
                Log("Virtual audio bridge: failed to create virtual audio devices");
                provider.Dispose();
                provider = null;
                return;
            }

            provider.TxDataAvailable += OnTxDataAvailable;
            running = true;
            Log($"Virtual audio bridge started (source={provider.SourceName}, sink={provider.SinkName})");
        }

        private void Stop()
        {
            if (!running) return;
            Log("Virtual audio bridge stopping...");
            running = false;

            if (provider != null)
            {
                provider.TxDataAvailable -= OnTxDataAvailable;
                provider.Destroy();
                provider.Dispose();
                provider = null;
            }

            Log("Virtual audio bridge stopped");
        }

        private int GetFirstConnectedRadioId()
        {
            var radios = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (radios is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    var prop = item.GetType().GetProperty("DeviceId");
                    if (prop != null)
                    {
                        object val = prop.GetValue(item);
                        if (val is int id && id > 0) return id;
                    }
                }
            }
            return -1;
        }

        private void Log(string message)
        {
            broker?.LogInfo(message);
        }

        public void Dispose()
        {
            Stop();
            broker?.Dispose();
        }
    }
}
