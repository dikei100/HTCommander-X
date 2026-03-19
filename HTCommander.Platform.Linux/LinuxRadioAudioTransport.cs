/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Tmds.DBus;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux Bluetooth transport for the radio audio channel using BlueZ/RFCOMM.
    /// Connects to the GenericAudio RFCOMM service (UUID: 00001203-0000-1000-8000-00805f9b34fb).
    /// </summary>
    public class LinuxRadioAudioTransport : IRadioAudioTransport
    {
        private Socket rfcommSocket = null;
        private Stream inputStream = null;
        private Stream outputStream = null;
        private bool _isConnected = false;
        private bool _disposed = false;

        // GenericAudio UUID used by these radios for audio channel
        private const string GENERIC_AUDIO_UUID = "00001203-0000-1000-8000-00805f9b34fb";
        private const string BlueZBusName = "org.bluez";
        private const string AdapterPath = "/org/bluez/hci0";

        public bool IsConnected => _isConnected;

        public async Task<bool> ConnectAsync(string macAddress, CancellationToken cancellationToken)
        {
            try
            {
                string mac = macAddress.Replace(":", "").Replace("-", "").ToUpper();
                string formattedMac = string.Join("_", Enumerable.Range(0, 6).Select(i => mac.Substring(i * 2, 2)));
                string devicePath = $"{AdapterPath}/dev_{formattedMac}";

                using var connection = new Connection(Address.System);
                await connection.ConnectAsync();
                var device = connection.CreateProxy<IDevice1>(BlueZBusName, devicePath);

                // Use ConnectProfile with GenericAudio UUID
                await device.ConnectProfileAsync(GENERIC_AUDIO_UUID);

                // Create RFCOMM socket
                byte[] bdaddr = ParseMacAddress(mac);
                rfcommSocket = CreateRfcommSocket(bdaddr, 2); // Audio typically on channel 2

                if (rfcommSocket == null) return false;

                inputStream = new NetworkStream(rfcommSocket, false);
                outputStream = new NetworkStream(rfcommSocket, false);
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
            try { inputStream?.Close(); } catch (Exception) { }
            try { inputStream?.Dispose(); } catch (Exception) { }
            inputStream = null;

            try { outputStream?.Close(); } catch (Exception) { }
            try { outputStream?.Dispose(); } catch (Exception) { }
            outputStream = null;

            try { rfcommSocket?.Close(); } catch (Exception) { }
            try { rfcommSocket?.Dispose(); } catch (Exception) { }
            rfcommSocket = null;
        }

        public async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (inputStream == null) return 0;
            return await inputStream.ReadAsync(buffer, offset, count, cancellationToken);
        }

        public async Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
        {
            if (outputStream == null) return;
            await outputStream.WriteAsync(buffer, offset, count, cancellationToken);
        }

        public async Task FlushAsync(CancellationToken cancellationToken)
        {
            if (outputStream == null) return;
            await outputStream.FlushAsync(cancellationToken);
        }

        public void OnPause() { }
        public void OnResume() { }

        private static byte[] ParseMacAddress(string mac)
        {
            mac = mac.Replace(":", "").Replace("-", "");
            byte[] bytes = new byte[6];
            for (int i = 0; i < 6; i++)
                bytes[i] = Convert.ToByte(mac.Substring(i * 2, 2), 16);
            return bytes;
        }

        private Socket CreateRfcommSocket(byte[] bdaddr, int channel)
        {
            try
            {
                int fd = NativeMethods.socket(31, 1, 3); // AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM
                if (fd < 0) return null;

                var addr = new NativeMethods.sockaddr_rc();
                addr.rc_family = 31;
                addr.rc_channel = (byte)channel;
                addr.rc_bdaddr = new byte[6];
                for (int i = 0; i < 6; i++)
                    addr.rc_bdaddr[i] = bdaddr[5 - i];

                int size = Marshal.SizeOf(addr);
                IntPtr addrPtr = Marshal.AllocHGlobal(size);
                try
                {
                    Marshal.StructureToPtr(addr, addrPtr, false);
                    int result = NativeMethods.connect(fd, addrPtr, size);
                    if (result < 0)
                    {
                        NativeMethods.close(fd);
                        return null;
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(addrPtr);
                }

                var safeHandle = new SafeSocketHandle((IntPtr)fd, true);
                return new Socket(safeHandle);
            }
            catch (Exception)
            {
                return null;
            }
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                Disconnect();
                _disposed = true;
            }
        }

        private static class NativeMethods
        {
            [StructLayout(LayoutKind.Sequential)]
            public struct sockaddr_rc
            {
                public ushort rc_family;
                [MarshalAs(UnmanagedType.ByValArray, SizeConst = 6)]
                public byte[] rc_bdaddr;
                public byte rc_channel;
            }

            [DllImport("libc", SetLastError = true)]
            public static extern int socket(int domain, int type, int protocol);

            [DllImport("libc", SetLastError = true)]
            public static extern int connect(int sockfd, IntPtr addr, int addrlen);

            [DllImport("libc", SetLastError = true)]
            public static extern int close(int fd);
        }
    }
}
