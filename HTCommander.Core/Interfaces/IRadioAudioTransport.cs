/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace HTCommander
{
    /// <summary>
    /// Platform-agnostic Bluetooth transport for the radio audio channel.
    /// Separated from audio codec logic so the codec stays in Core.
    /// </summary>
    public interface IRadioAudioTransport : IDisposable
    {
        /// <summary>
        /// Connect to the radio's audio RFCOMM service.
        /// </summary>
        /// <param name="macAddress">The MAC address of the radio.</param>
        /// <param name="cancellationToken">Cancellation token.</param>
        /// <returns>True if connected successfully.</returns>
        Task<bool> ConnectAsync(string macAddress, CancellationToken cancellationToken);

        /// <summary>
        /// Disconnect and release all Bluetooth resources.
        /// </summary>
        void Disconnect();

        /// <summary>
        /// Read data from the audio stream.
        /// </summary>
        Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken);

        /// <summary>
        /// Write data to the audio stream.
        /// </summary>
        Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken);

        /// <summary>
        /// Flush the output stream.
        /// </summary>
        Task FlushAsync(CancellationToken cancellationToken);

        /// <summary>
        /// Whether the transport is currently connected.
        /// </summary>
        bool IsConnected { get; }

        void OnPause();
        void OnResume();
    }
}
