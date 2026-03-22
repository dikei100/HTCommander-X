/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Rfcomm;
using Windows.Networking.Sockets;

namespace HTCommander.Platform.Windows
{
    /// <summary>
    /// Windows WinRT Bluetooth transport for the radio audio channel.
    /// Connects to the GenericAudio RFCOMM service (UUID: 00001203-0000-1000-8000-00805f9b34fb).
    /// </summary>
    public class WinRadioAudioTransport : IRadioAudioTransport
    {
        private StreamSocket bluetoothSocket = null;
        private RfcommDeviceService rfcommService = null;
        private Stream winRtInputStream = null;
        private Stream winRtOutputStream = null;
        private volatile bool _isConnected = false;
        private volatile bool _disposed = false;

        // GenericAudio UUID used by these radios for audio channel
        private static readonly Guid GenericAudioUuid = new Guid("00001203-0000-1000-8000-00805f9b34fb");

        public bool IsConnected => _isConnected;

        public async Task<bool> ConnectAsync(string macAddress, CancellationToken cancellationToken)
        {
            try
            {
                ulong btAddress = Convert.ToUInt64(macAddress.Replace(":", "").Replace("-", ""), 16);
                var btDevice = await BluetoothDevice.FromBluetoothAddressAsync(btAddress);
                if (btDevice == null) return false;

                // Search for GenericAudio RFCOMM service
                var rfcommServices = await btDevice.GetRfcommServicesAsync();
                RfcommDeviceService audioService = null;

                foreach (var service in rfcommServices.Services)
                {
                    if (service.ServiceId.Uuid == GenericAudioUuid)
                    {
                        audioService = service;
                        break;
                    }
                }

                // Fallback to first available service
                if (audioService == null && rfcommServices.Services.Count > 0)
                {
                    audioService = rfcommServices.Services[0];
                }

                if (audioService == null) return false;

                rfcommService = audioService;
                bluetoothSocket = new StreamSocket();
                await bluetoothSocket.ConnectAsync(
                    rfcommService.ConnectionHostName,
                    rfcommService.ConnectionServiceName,
                    SocketProtectionLevel.BluetoothEncryptionAllowNullAuthentication);

                winRtInputStream = bluetoothSocket.InputStream.AsStreamForRead();
                winRtOutputStream = bluetoothSocket.OutputStream.AsStreamForWrite();
                _isConnected = true;
                return true;
            }
            catch (Exception)
            {
                Disconnect();
                return false;
            }
        }

        public void Disconnect()
        {
            _isConnected = false;
            try { winRtInputStream?.Close(); } catch (Exception) { }
            try { winRtInputStream?.Dispose(); } catch (Exception) { }
            winRtInputStream = null;

            try { winRtOutputStream?.Close(); } catch (Exception) { }
            try { winRtOutputStream?.Dispose(); } catch (Exception) { }
            winRtOutputStream = null;

            try { bluetoothSocket?.Dispose(); } catch (Exception) { }
            bluetoothSocket = null;

            try { rfcommService?.Dispose(); } catch (Exception) { }
            rfcommService = null;
        }

        public async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (winRtInputStream == null) return 0;
            return await winRtInputStream.ReadAsync(buffer, offset, count, cancellationToken);
        }

        public async Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (winRtOutputStream == null) return;
            await winRtOutputStream.WriteAsync(buffer, offset, count, cancellationToken);
        }

        public async Task FlushAsync(CancellationToken cancellationToken)
        {
            if (winRtOutputStream == null) return;
            await winRtOutputStream.FlushAsync(cancellationToken);
        }

        public void OnPause() { }
        public void OnResume() { }

        public void Dispose()
        {
            if (!_disposed)
            {
                Disconnect();
                _disposed = true;
            }
        }
    }
}
