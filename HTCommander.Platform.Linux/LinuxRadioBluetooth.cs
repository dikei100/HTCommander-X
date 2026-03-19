/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Tmds.DBus;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux Bluetooth transport using BlueZ D-Bus + native RFCOMM sockets.
    /// Strategy: Register an SPP profile with BlueZ ProfileManager1, then connect.
    /// BlueZ calls our profile with a ready-to-use file descriptor on the correct channel.
    /// </summary>
    public class LinuxRadioBluetooth : IRadioBluetooth
    {
        private IRadioHost parent;
        private bool running = false;
        private int rfcommFd = -1;
        private Stream inputStream = null;
        private Stream outputStream = null;
        private CancellationTokenSource connectionCts = null;
        private readonly object connectionLock = new object();
        private Task connectionTask = null;
        private bool isConnecting = false;
        private bool _disposed = false;

        // Serial Port Profile UUID
        private const string SPP_UUID = "00001101-0000-1000-8000-00805f9b34fb";
        // Unique profile path for this instance
        private static int _profileCounter = 0;
        private string _profilePath;

        // Signaling: BlueZ delivers the fd via NewConnection callback
        private TaskCompletionSource<int> _fdReady;

        public event Action OnConnected;
        public event Action<Exception, byte[]> ReceivedData;

        private static readonly string[] TargetDeviceNames = { "UV-PRO", "UV-50PRO", "GA-5WB", "VR-N75", "VR-N76", "VR-N7500", "VR-N7600" };

        private const string BlueZBusName = "org.bluez";
        private const string AdapterPath = "/org/bluez/hci0";

        public LinuxRadioBluetooth(IRadioHost parent)
        {
            this.parent = parent;
            _profilePath = $"/htcommander/spp_profile_{Interlocked.Increment(ref _profileCounter)}";
        }

        private void Debug(string msg) { parent?.Debug("Transport: " + msg); }

        public Task<bool> RequestPermissionsAsync() => Task.FromResult(true);

        public async Task<bool> CheckBluetoothAsync()
        {
            try
            {
                using var connection = new Connection(Address.System);
                await connection.ConnectAsync();
                var adapter = connection.CreateProxy<IAdapter1>(BlueZBusName, AdapterPath);
                var powered = await adapter.GetAsync("Powered");
                return powered is bool b && b;
            }
            catch (Exception) { return false; }
        }

        public async Task<string[]> GetDeviceNames()
        {
            List<string> deviceNames = new List<string>();
            try
            {
                using var connection = new Connection(Address.System);
                await connection.ConnectAsync();
                var manager = connection.CreateProxy<IObjectManager>(BlueZBusName, "/");
                var objects = await manager.GetManagedObjectsAsync();

                foreach (var path in objects.Keys)
                {
                    if (objects[path].ContainsKey("org.bluez.Device1"))
                    {
                        var props = objects[path]["org.bluez.Device1"];
                        if (props.TryGetValue("Name", out object nameObj) && nameObj is string name)
                        {
                            if (!deviceNames.Contains(name))
                                deviceNames.Add(name);
                        }
                    }
                }
            }
            catch (Exception) { }
            deviceNames.Sort();
            return deviceNames.ToArray();
        }

        public async Task<CompatibleDevice[]> FindCompatibleDevices()
        {
            List<CompatibleDevice> compatibleDevices = new List<CompatibleDevice>();
            List<string> macs = new List<string>();

            try
            {
                using var connection = new Connection(Address.System);
                await connection.ConnectAsync();
                var manager = connection.CreateProxy<IObjectManager>(BlueZBusName, "/");
                var objects = await manager.GetManagedObjectsAsync();

                foreach (var path in objects.Keys)
                {
                    if (!objects[path].ContainsKey("org.bluez.Device1")) continue;
                    var props = objects[path]["org.bluez.Device1"];

                    string name = null, address = null;
                    if (props.TryGetValue("Name", out object nameObj)) name = nameObj as string;
                    if (props.TryGetValue("Address", out object addrObj)) address = addrObj as string;

                    if (name == null || address == null) continue;
                    if (!TargetDeviceNames.Contains(name)) continue;

                    string mac = address.Replace(":", "").ToUpper();
                    if (!macs.Contains(mac))
                    {
                        macs.Add(mac);
                        compatibleDevices.Add(new CompatibleDevice(name, mac));
                    }
                }
            }
            catch (Exception) { }
            return compatibleDevices.ToArray();
        }

        public bool Connect()
        {
            lock (connectionLock)
            {
                if (running || isConnecting) return false;
                isConnecting = true;
            }
            connectionTask = Task.Run(() => StartAsync());
            return true;
        }

        public void Disconnect()
        {
            lock (connectionLock)
            {
                if (!running && connectionTask == null) return;
                running = false;
                try { connectionCts?.Cancel(); } catch { }
            }

            if (connectionTask != null)
            {
                try { connectionTask.Wait(TimeSpan.FromSeconds(3)); } catch { }
            }

            lock (connectionLock)
            {
                try { inputStream?.Close(); } catch { }
                try { inputStream?.Dispose(); } catch { }
                inputStream = null;
                try { outputStream?.Close(); } catch { }
                try { outputStream?.Dispose(); } catch { }
                outputStream = null;

                if (rfcommFd >= 0) { try { NativeMethods.close(rfcommFd); } catch { } rfcommFd = -1; }

                try { connectionCts?.Dispose(); } catch { }
                connectionCts = null;
                connectionTask = null;
            }
            Thread.Sleep(100);
        }

        public void EnqueueWrite(int expectedResponse, byte[] cmdData)
        {
            if (!running || rfcommFd < 0) return;
            byte[] bytes = GaiaEncode(cmdData);
            int written = NativeMethods.write(rfcommFd, bytes, bytes.Length);
            if (written < 0)
                Debug($"write() failed: errno={Marshal.GetLastWin32Error()}");
        }

        public void OnPause() { }
        public void OnResume() { }

        #region GAIA Protocol

        private static int GaiaDecode(byte[] data, int index, int len, out byte[] cmd)
        {
            cmd = null;
            if (len < 8) return 0;
            if (data[index] != 0xFF || data[index + 1] != 0x01) return -1;
            byte payloadLen = data[index + 3];
            int hasChecksum = data[index + 2] & 1;
            int totalLen = payloadLen + 8 + hasChecksum;
            if (totalLen > len) return 0;
            cmd = new byte[4 + payloadLen];
            Array.Copy(data, index + 4, cmd, 0, cmd.Length);
            return totalLen;
        }

        private static byte[] GaiaEncode(byte[] cmd)
        {
            byte[] bytes = new byte[cmd.Length + 4];
            bytes[0] = 0xFF;
            bytes[1] = 0x01;
            bytes[3] = (byte)(cmd.Length - 4);
            Array.Copy(cmd, 0, bytes, 4, cmd.Length);
            return bytes;
        }

        #endregion

        #region Connection

        private async void StartAsync()
        {
            CancellationToken ct;
            lock (connectionLock)
            {
                connectionCts = new CancellationTokenSource();
                ct = connectionCts.Token;
            }

            string mac = parent.MacAddress.Replace(":", "").Replace("-", "").ToUpper();
            string macColon = string.Join(":", Enumerable.Range(0, 6).Select(i => mac.Substring(i * 2, 2)));
            string formattedMac = string.Join("_", Enumerable.Range(0, 6).Select(i => mac.Substring(i * 2, 2)));
            string devicePath = $"{AdapterPath}/dev_{formattedMac}";

            int retry = 3;
            while (retry > 0 && !ct.IsCancellationRequested)
            {
                Connection dbusConn = null;
                try
                {
                    Debug($"Connecting to {macColon} (attempt {4 - retry}/3)...");

                    // Open a persistent D-Bus connection for the profile registration
                    dbusConn = new Connection(Address.System);
                    await dbusConn.ConnectAsync();

                    // Step 1: Ensure ACL-level connection
                    var device = dbusConn.CreateProxy<IDevice1>(BlueZBusName, devicePath);
                    try
                    {
                        var connected = await device.GetAsync("Connected");
                        if (!(connected is bool b && b))
                        {
                            Debug("Connecting at ACL level...");
                            await device.ConnectAsync();
                            await Task.Delay(2000, ct);
                        }
                        else
                        {
                            Debug("Device already connected at ACL level");
                        }
                    }
                    catch (Exception ex)
                    {
                        Debug($"ACL connect: {ex.Message}");
                    }

                    // Step 2: Register SPP profile and connect
                    Debug("Registering SPP profile with BlueZ...");
                    _fdReady = new TaskCompletionSource<int>();

                    // Register our profile handler object on D-Bus
                    var profileHandler = new SppProfileHandler(this);
                    await dbusConn.RegisterObjectAsync(profileHandler);

                    // Register the profile with BlueZ ProfileManager1
                    var profileManager = dbusConn.CreateProxy<IProfileManager1>(BlueZBusName, "/org/bluez");
                    var options = new Dictionary<string, object>
                    {
                        { "Role", "client" },
                        { "Channel", (ushort)0 },  // 0 = auto (BlueZ picks via SDP)
                        { "RequireAuthentication", false },
                        { "RequireAuthorization", false }
                    };

                    try
                    {
                        await profileManager.RegisterProfileAsync(new ObjectPath(_profilePath), SPP_UUID, options);
                        Debug("SPP profile registered");
                    }
                    catch (Exception ex)
                    {
                        Debug($"Profile registration: {ex.Message}");
                        // May already be registered, try connecting anyway
                    }

                    // Step 3: Ask BlueZ to connect using our profile
                    Debug("Requesting ConnectProfile...");
                    try
                    {
                        await device.ConnectProfileAsync(SPP_UUID);
                    }
                    catch (Exception ex)
                    {
                        Debug($"ConnectProfile: {ex.Message}");
                    }

                    // Step 4: Wait for BlueZ to deliver the fd via NewConnection
                    Debug("Waiting for BlueZ to deliver file descriptor...");
                    using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                    cts.CancelAfter(TimeSpan.FromSeconds(10));
                    cts.Token.Register(() => _fdReady.TrySetCanceled());

                    try
                    {
                        rfcommFd = await _fdReady.Task;
                        Debug($"Got fd {rfcommFd} from BlueZ NewConnection");
                        retry = -2;
                    }
                    catch (OperationCanceledException)
                    {
                        Debug("Timeout waiting for NewConnection — BlueZ did not deliver fd");

                        // Fallback: try native RFCOMM socket with channel probing
                        Debug("Falling back to direct RFCOMM channel probing...");
                        byte[] bdaddr = ParseMacAddress(mac);
                        rfcommFd = ProbeChannels(bdaddr);
                        if (rfcommFd >= 0)
                        {
                            retry = -2;
                        }
                        else
                        {
                            retry--;
                            if (retry > 0) await Task.Delay(2000, ct);
                        }
                    }
                    finally
                    {
                        // Unregister profile (best effort)
                        try { await profileManager.UnregisterProfileAsync(new ObjectPath(_profilePath)); } catch { }
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    retry--;
                    Debug("Connect failed: " + ex.Message);
                    if (rfcommFd >= 0) { try { NativeMethods.close(rfcommFd); } catch { } rfcommFd = -1; }
                    if (retry > 0) await Task.Delay(2000, ct);
                }
                finally
                {
                    dbusConn?.Dispose();
                }
            }

            if (retry != -2)
            {
                lock (connectionLock) { isConnecting = false; }
                parent.Disconnect("Unable to connect", RadioState.UnableToConnect);
                return;
            }

            Debug("Connected.");
            RunReadLoop(ct);
        }

        /// <summary>
        /// Called by BlueZ via our registered Profile1 when the RFCOMM connection is established.
        /// </summary>
        internal void OnNewConnection(ObjectPath device, int fd, IDictionary<string, object> properties)
        {
            Debug($"BlueZ NewConnection: device={device}, fd={fd}");
            _fdReady?.TrySetResult(fd);
        }

        /// <summary>
        /// Fallback: probe RFCOMM channels 1-30 with native sockets.
        /// Sends a GAIA command and checks if the connection stays alive.
        /// </summary>
        private int ProbeChannels(byte[] bdaddr)
        {
            Debug("Probing RFCOMM channels 1-30...");
            for (int ch = 1; ch <= 30; ch++)
            {
                int fd = CreateRfcommFd(bdaddr, ch);
                if (fd < 0) continue;

                // Send GAIA GET_DEV_ID and check for response
                byte[] gaiaCmd = GaiaEncode(new byte[] { 0x00, 0x02, 0x00, 0x01 });
                int sent = NativeMethods.write(fd, gaiaCmd, gaiaCmd.Length);
                if (sent < 0) { NativeMethods.close(fd); continue; }

                // Wait briefly for data or timeout
                byte[] buf = new byte[64];
                // Set non-blocking with timeout via poll
                var pfd = new NativeMethods.pollfd { fd = fd, events = 1 /* POLLIN */ };
                int pollResult = NativeMethods.poll(ref pfd, 1, 1500);

                if (pollResult > 0 && (pfd.revents & 1) != 0)
                {
                    int read = NativeMethods.read(fd, buf, buf.Length);
                    if (read > 0)
                    {
                        Debug($"Channel {ch}: got {read} bytes — using this channel");
                        return fd;
                    }
                }
                else if (pollResult == 0)
                {
                    // Timeout — socket still alive, this might be the right channel
                    // Check if socket is still connected
                    int err = 0;
                    int errLen = 4;
                    NativeMethods.getsockopt(fd, 1 /* SOL_SOCKET */, 4 /* SO_ERROR */, ref err, ref errLen);
                    if (err == 0)
                    {
                        Debug($"Channel {ch}: timeout but socket alive — using this channel");
                        return fd;
                    }
                }

                Debug($"Channel {ch}: not responsive");
                NativeMethods.close(fd);
            }
            Debug("No responsive channel found");
            return -1;
        }

        private void RunReadLoop(CancellationToken ct)
        {
            try
            {
                byte[] accumulator = new byte[4096];
                int accumulatorPtr = 0, accumulatorLen = 0;

                lock (connectionLock)
                {
                    isConnecting = false;
                    if (ct.IsCancellationRequested)
                    {
                        running = false;
                        if (rfcommFd >= 0) { NativeMethods.close(rfcommFd); rfcommFd = -1; }
                        return;
                    }
                }

                // Verify the fd is valid and check socket type
                int fcntlResult = NativeMethods.fcntl(rfcommFd, 1 /* F_GETFD */);
                Debug($"fd {rfcommFd} fcntl F_GETFD = {fcntlResult} (errno={Marshal.GetLastWin32Error()})");
                if (fcntlResult < 0)
                {
                    Debug("ERROR: fd is not valid!");
                    lock (connectionLock) { isConnecting = false; }
                    parent.Disconnect("Invalid file descriptor", RadioState.UnableToConnect);
                    return;
                }

                // Check socket type and domain
                int sockType = 0, sockTypeLen = 4;
                NativeMethods.getsockopt(rfcommFd, 1 /* SOL_SOCKET */, 3 /* SO_TYPE */, ref sockType, ref sockTypeLen);
                int sockDomain = 0, sockDomainLen = 4;
                NativeMethods.getsockopt(rfcommFd, 1 /* SOL_SOCKET */, 39 /* SO_DOMAIN */, ref sockDomain, ref sockDomainLen);
                int sockProto = 0, sockProtoLen = 4;
                NativeMethods.getsockopt(rfcommFd, 1 /* SOL_SOCKET */, 38 /* SO_PROTOCOL */, ref sockProto, ref sockProtoLen);
                Debug($"Socket info: type={sockType} (1=STREAM), domain={sockDomain} (31=AF_BLUETOOTH), protocol={sockProto} (3=BTPROTO_RFCOMM)");

                // Check if socket is non-blocking
                int flags = NativeMethods.fcntl(rfcommFd, 3 /* F_GETFL */);
                bool nonBlocking = (flags & 0x800 /* O_NONBLOCK */) != 0;
                Debug($"Socket flags=0x{flags:X}, nonBlocking={nonBlocking}");
                if (nonBlocking)
                {
                    // Clear non-blocking — we want blocking reads with poll() timeout
                    NativeMethods.fcntl3(rfcommFd, 4 /* F_SETFL */, flags & ~0x800);
                    Debug("Cleared O_NONBLOCK flag");
                }

                running = true;
                OnConnected?.Invoke();

                int pollTimeouts = 0;
                // Use direct read()/write() on the fd — avoids Socket/NetworkStream issues with BT fds
                while (running && !ct.IsCancellationRequested)
                {
                    // Use poll() to wait for data with a timeout so we can check cancellation
                    var pfd = new NativeMethods.pollfd { fd = rfcommFd, events = 1 /* POLLIN */ };
                    int pollResult = NativeMethods.poll(ref pfd, 1, 1000); // 1 second timeout

                    if (pollResult < 0)
                    {
                        int errno = Marshal.GetLastWin32Error();
                        if (errno == 4) continue; // EINTR — interrupted, just retry
                        Debug($"poll() error: errno={errno}");
                        break;
                    }

                    if (pollResult == 0)
                    {
                        // Every 10 timeouts, log that we're still waiting
                        if (++pollTimeouts % 10 == 0) Debug($"poll() waiting... ({pollTimeouts}s, no data from radio)");
                        continue;
                    }

                    if ((pfd.revents & (4 | 8 | 16)) != 0) // POLLERR | POLLHUP | POLLNVAL
                    {
                        Debug($"poll() revents={pfd.revents} — connection lost");
                        break;
                    }

                    if ((pfd.revents & 1) == 0) continue; // no POLLIN

                    // Read into a temp buffer, then copy to accumulator at the right offset
                    int space = accumulator.Length - (accumulatorPtr + accumulatorLen);
                    if (space <= 0) { accumulatorPtr = 0; accumulatorLen = 0; space = accumulator.Length; }

                    byte[] readBuf = new byte[Math.Min(space, 1024)];
                    int bytesRead = NativeMethods.read(rfcommFd, readBuf, readBuf.Length);

                    if (bytesRead < 0)
                    {
                        int errno = Marshal.GetLastWin32Error();
                        if (errno == 11 || errno == 4) continue; // EAGAIN or EINTR
                        Debug($"read() error: errno={errno}");
                        break;
                    }

                    if (!running) break;
                    if (bytesRead == 0)
                    {
                        Debug("read() returned 0 — remote closed connection");
                        break;
                    }

                    Array.Copy(readBuf, 0, accumulator, accumulatorPtr + accumulatorLen, bytesRead);
                    accumulatorLen += bytesRead;

                    if (accumulatorLen < 8) continue;

                    int cmdSize;
                    byte[] cmd;
                    while ((cmdSize = GaiaDecode(accumulator, accumulatorPtr, accumulatorLen, out cmd)) != 0)
                    {
                        if (cmdSize < 0) cmdSize = accumulatorLen;
                        accumulatorPtr += cmdSize;
                        accumulatorLen -= cmdSize;
                        if (cmd != null) ReceivedData?.Invoke(null, cmd);
                    }

                    if (accumulatorLen == 0) accumulatorPtr = 0;
                    if (accumulatorPtr > 2048)
                    {
                        Array.Copy(accumulator, accumulatorPtr, accumulator, 0, accumulatorLen);
                        accumulatorPtr = 0;
                    }
                }
            }
            catch (Exception ex)
            {
                if (running) Debug($"Connection error: {ex.Message}");
            }
            finally
            {
                lock (connectionLock) { running = false; isConnecting = false; }
                lock (connectionLock)
                {
                    if (rfcommFd >= 0) { try { NativeMethods.close(rfcommFd); } catch { } rfcommFd = -1; }
                }
                Debug("Connection closed.");
                parent.Disconnect("Connection closed.", RadioState.Disconnected);
            }
        }

        #endregion

        #region Native RFCOMM

        private static byte[] ParseMacAddress(string mac)
        {
            mac = mac.Replace(":", "").Replace("-", "");
            byte[] bytes = new byte[6];
            for (int i = 0; i < 6; i++)
                bytes[i] = Convert.ToByte(mac.Substring(i * 2, 2), 16);
            return bytes;
        }

        private int CreateRfcommFd(byte[] bdaddr, int channel)
        {
            int fd = NativeMethods.socket(31, 1, 3); // AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM
            if (fd < 0) return -1;

            byte[] addr = new byte[10];
            addr[0] = 31; addr[1] = 0; // AF_BLUETOOTH
            for (int i = 0; i < 6; i++) addr[2 + i] = bdaddr[5 - i]; // reversed
            addr[8] = (byte)channel;

            IntPtr addrPtr = Marshal.AllocHGlobal(addr.Length);
            try
            {
                Marshal.Copy(addr, 0, addrPtr, addr.Length);
                int result = NativeMethods.connect(fd, addrPtr, addr.Length);
                if (result < 0) { NativeMethods.close(fd); return -1; }
            }
            finally { Marshal.FreeHGlobal(addrPtr); }

            return fd;
        }

        #endregion

        public void Dispose()
        {
            if (!_disposed) { Disconnect(); _disposed = true; }
        }

        private static class NativeMethods
        {
            [DllImport("libc", SetLastError = true)]
            public static extern int socket(int domain, int type, int protocol);
            [DllImport("libc", SetLastError = true)]
            public static extern int connect(int sockfd, IntPtr addr, int addrlen);
            [DllImport("libc", SetLastError = true)]
            public static extern int close(int fd);
            [DllImport("libc", SetLastError = true)]
            public static extern int write(int fd, byte[] buf, int count);
            [DllImport("libc", SetLastError = true)]
            public static extern int read(int fd, byte[] buf, int count);
            [DllImport("libc", SetLastError = true)]
            public static extern int getsockopt(int sockfd, int level, int optname, ref int optval, ref int optlen);

            [StructLayout(LayoutKind.Sequential)]
            public struct pollfd { public int fd; public short events; public short revents; }

            [DllImport("libc", SetLastError = true)]
            public static extern int poll(ref pollfd fds, int nfds, int timeout);

            [DllImport("libc", SetLastError = true)]
            public static extern int fcntl(int fd, int cmd);

            [DllImport("libc", SetLastError = true, EntryPoint = "fcntl")]
            public static extern int fcntl3(int fd, int cmd, int arg);
        }
    }

    /// <summary>
    /// BlueZ Profile1 D-Bus handler. Receives NewConnection callback with the fd.
    /// </summary>
    internal class SppProfileHandler : IProfile1
    {
        private readonly LinuxRadioBluetooth _owner;
        public ObjectPath ObjectPath { get; }

        public SppProfileHandler(LinuxRadioBluetooth owner)
        {
            _owner = owner;
            // Use reflection to get the profile path
            var field = typeof(LinuxRadioBluetooth).GetField("_profilePath",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            ObjectPath = new ObjectPath((string)field.GetValue(owner));
        }

        [DllImport("libc", SetLastError = true)]
        private static extern int dup(int oldfd);

        public Task NewConnectionAsync(ObjectPath device, CloseSafeHandle fd, IDictionary<string, object> properties)
        {
            // CRITICAL: dup() the fd before this method returns, because Tmds.DBus
            // will close the CloseSafeHandle (and thus the original fd) when we return.
            int originalFd = fd.DangerousGetHandle().ToInt32();
            int dupedFd = dup(originalFd);
            _owner.OnNewConnection(device, dupedFd, properties);
            return Task.CompletedTask;
        }

        public Task RequestDisconnectionAsync(ObjectPath device)
        {
            return Task.CompletedTask;
        }

        public Task ReleaseAsync()
        {
            return Task.CompletedTask;
        }
    }

    #region BlueZ D-Bus Interfaces

    [DBusInterface("org.bluez.Adapter1")]
    public interface IAdapter1 : IDBusObject
    {
        Task<object> GetAsync(string prop);
    }

    [DBusInterface("org.freedesktop.DBus.ObjectManager")]
    public interface IObjectManager : IDBusObject
    {
        Task<IDictionary<ObjectPath, IDictionary<string, IDictionary<string, object>>>> GetManagedObjectsAsync();
    }

    [DBusInterface("org.bluez.Device1")]
    public interface IDevice1 : IDBusObject
    {
        Task ConnectAsync();
        Task ConnectProfileAsync(string uuid);
        Task DisconnectAsync();
        Task<object> GetAsync(string prop);
    }

    [DBusInterface("org.bluez.ProfileManager1")]
    public interface IProfileManager1 : IDBusObject
    {
        Task RegisterProfileAsync(ObjectPath profile, string uuid, IDictionary<string, object> options);
        Task UnregisterProfileAsync(ObjectPath profile);
    }

    [DBusInterface("org.bluez.Profile1")]
    public interface IProfile1 : IDBusObject
    {
        Task NewConnectionAsync(ObjectPath device, CloseSafeHandle fd, IDictionary<string, object> properties);
        Task RequestDisconnectionAsync(ObjectPath device);
        Task ReleaseAsync();
    }

    #endregion
}
