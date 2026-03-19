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
    /// Platform-agnostic Bluetooth transport for radio command/response communication.
    /// Implementations: WinRadioBluetooth (WinRT), LinuxRadioBluetooth (BlueZ D-Bus).
    /// Android-ready: includes permission checking and lifecycle methods.
    /// </summary>
    public interface IRadioBluetooth : IDisposable
    {
        /// <summary>
        /// Request Bluetooth permissions. No-op on desktop, critical on Android.
        /// </summary>
        Task<bool> RequestPermissionsAsync();

        /// <summary>
        /// Check if Bluetooth is available and enabled on this platform.
        /// </summary>
        Task<bool> CheckBluetoothAsync();

        /// <summary>
        /// Get names of all paired/discovered Bluetooth devices.
        /// </summary>
        Task<string[]> GetDeviceNames();

        /// <summary>
        /// Find compatible radio devices (UV-PRO, VR-N75, etc.).
        /// </summary>
        Task<CompatibleDevice[]> FindCompatibleDevices();

        /// <summary>
        /// Initiate connection to the radio. Returns true if connection started successfully.
        /// </summary>
        bool Connect();

        /// <summary>
        /// Disconnect from the radio and release all resources.
        /// </summary>
        void Disconnect();

        /// <summary>
        /// Enqueue a GAIA-encoded command for transmission.
        /// </summary>
        void EnqueueWrite(int expectedResponse, byte[] cmdData);

        /// <summary>
        /// Called when the app is backgrounded (Android lifecycle). No-op on desktop.
        /// </summary>
        void OnPause();

        /// <summary>
        /// Called when the app returns to foreground (Android lifecycle). No-op on desktop.
        /// </summary>
        void OnResume();

        /// <summary>
        /// Fired when the Bluetooth connection is established.
        /// </summary>
        event Action OnConnected;

        /// <summary>
        /// Fired when data is received from the radio.
        /// Parameters: sender exception (null on success), received command bytes.
        /// </summary>
        event Action<Exception, byte[]> ReceivedData;
    }
}
