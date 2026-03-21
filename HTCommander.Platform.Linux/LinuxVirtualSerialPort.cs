/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux PTY pair implementation of IVirtualSerialPort.
    /// Creates a master/slave PTY pair via openpty() for Kenwood CAT emulation.
    /// Symlinks the slave to ~/.config/HTCommander/cat-port for a stable path.
    /// </summary>
    public class LinuxVirtualSerialPort : IVirtualSerialPort
    {
        private int masterFd = -1;
        private int slaveFd = -1;
        private string slavePath;
        private string symlinkPath;
        private Thread readThread;
        private volatile bool running = false;

        public string DevicePath => symlinkPath ?? slavePath;
        public bool IsRunning => running;
        public event Action<byte[], int> DataReceived;

        // P/Invoke for PTY and terminal operations
        [DllImport("libc", SetLastError = true)]
        private static extern int openpty(out int master, out int slave, IntPtr name, IntPtr termp, IntPtr winp);

        [DllImport("libc", SetLastError = true)]
        private static extern IntPtr ttyname(int fd);

        [DllImport("libc", SetLastError = true)]
        private static extern int close(int fd);

        [DllImport("libc", SetLastError = true)]
        private static extern IntPtr read(int fd, byte[] buf, IntPtr count);

        [DllImport("libc", SetLastError = true)]
        private static extern IntPtr write(int fd, byte[] buf, IntPtr count);

        [DllImport("libc", SetLastError = true)]
        private static extern int tcgetattr(int fd, byte[] termios);

        [DllImport("libc", SetLastError = true)]
        private static extern int tcsetattr(int fd, int optional_actions, byte[] termios);

        [DllImport("libc", SetLastError = true)]
        private static extern int fcntl(int fd, int cmd, int arg);

        private const int F_GETFL = 3;
        private const int F_SETFL = 4;
        private const int O_NONBLOCK = 2048;
        private const int TCSANOW = 0;

        public bool Create()
        {
            try
            {
                int result = openpty(out masterFd, out slaveFd, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                if (result != 0)
                {
                    return false;
                }

                // Get slave device path
                IntPtr namePtr = ttyname(slaveFd);
                if (namePtr == IntPtr.Zero)
                {
                    Cleanup();
                    return false;
                }
                slavePath = Marshal.PtrToStringAnsi(namePtr);

                // Configure raw mode on master
                ConfigureRawMode(masterFd);

                // Set master to non-blocking
                int flags = fcntl(masterFd, F_GETFL, 0);
                fcntl(masterFd, F_SETFL, flags | O_NONBLOCK);

                // Create symlink for stable path
                string configDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    ".config", "HTCommander");
                Directory.CreateDirectory(configDir);
                symlinkPath = Path.Combine(configDir, "cat-port");

                try
                {
                    // Atomic symlink replacement: create temp symlink then rename
                    // This eliminates the TOCTOU window between delete and create
                    string tempLink = symlinkPath + "." + Guid.NewGuid().ToString("N").Substring(0, 8);
                    try
                    {
                        File.CreateSymbolicLink(tempLink, slavePath);
                        // Atomic rename — overwrites existing symlink
                        File.Move(tempLink, symlinkPath, overwrite: true);
                    }
                    catch
                    {
                        // Cleanup temp if rename failed
                        try { File.Delete(tempLink); } catch { }

                        // Fallback: verify existing file is a symlink before deleting
                        var linkInfo = new FileInfo(symlinkPath);
                        if (linkInfo.Exists && (linkInfo.Attributes & FileAttributes.ReparsePoint) == 0)
                        {
                            // Not a symlink — refuse to delete a regular file
                            symlinkPath = slavePath;
                        }
                        else
                        {
                            if (linkInfo.Exists) File.Delete(symlinkPath);
                            if (symlinkPath != slavePath)
                                File.CreateSymbolicLink(symlinkPath, slavePath);
                        }
                    }
                }
                catch
                {
                    // Symlink failed, use raw path
                    symlinkPath = slavePath;
                }

                // Start read thread
                running = true;
                readThread = new Thread(ReadLoop)
                {
                    IsBackground = true,
                    Name = "CATSerialRead"
                };
                readThread.Start();

                return true;
            }
            catch
            {
                Cleanup();
                return false;
            }
        }

        private void ConfigureRawMode(int fd)
        {
            // cfmakeraw equivalent: read termios, set raw flags, write back
            byte[] termios = new byte[256]; // Large enough for any platform
            if (tcgetattr(fd, termios) == 0)
            {
                // cfmakeraw: clear ECHO, ICANON, ISIG, IEXTEN, etc.
                // On Linux x86_64, termios struct layout:
                // c_iflag at offset 0 (4 bytes)
                // c_oflag at offset 4 (4 bytes)
                // c_cflag at offset 8 (4 bytes)
                // c_lflag at offset 12 (4 bytes)
                uint iflag = BitConverter.ToUInt32(termios, 0);
                uint oflag = BitConverter.ToUInt32(termios, 4);
                uint cflag = BitConverter.ToUInt32(termios, 8);
                uint lflag = BitConverter.ToUInt32(termios, 12);

                // Clear input flags
                iflag &= ~(uint)(0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040 | 0x0100);
                // IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON

                // Clear output flags
                oflag &= ~(uint)0x0001; // OPOST

                // Clear local flags
                lflag &= ~(uint)(0x0008 | 0x0002 | 0x0001 | 0x8000 | 0x0010);
                // ECHO | ECHONL | ICANON | IEXTEN | ISIG

                // Set character size CS8
                cflag &= ~(uint)(0x0030); // CSIZE
                cflag |= 0x0030; // CS8
                cflag &= ~(uint)0x0100; // PARENB

                BitConverter.GetBytes(iflag).CopyTo(termios, 0);
                BitConverter.GetBytes(oflag).CopyTo(termios, 4);
                BitConverter.GetBytes(cflag).CopyTo(termios, 8);
                BitConverter.GetBytes(lflag).CopyTo(termios, 12);

                tcsetattr(fd, TCSANOW, termios);
            }
        }

        private void ReadLoop()
        {
            byte[] buffer = new byte[4096];

            while (running)
            {
                try
                {
                    IntPtr bytesRead = read(masterFd, buffer, (IntPtr)buffer.Length);
                    int n = bytesRead.ToInt32();

                    if (n > 0)
                    {
                        byte[] data = new byte[n];
                        Array.Copy(buffer, data, n);
                        DataReceived?.Invoke(data, n);
                    }
                    else if (n < 0)
                    {
                        int errno = Marshal.GetLastWin32Error();
                        if (errno == 11 || errno == 35) // EAGAIN / EWOULDBLOCK
                        {
                            Thread.Sleep(20);
                        }
                        else
                        {
                            break; // Fatal error
                        }
                    }
                    else
                    {
                        Thread.Sleep(20);
                    }
                }
                catch
                {
                    break;
                }
            }
        }

        public void Write(byte[] data, int offset, int count)
        {
            if (masterFd < 0 || !running) return;

            byte[] buf = data;
            if (offset != 0 || count != data.Length)
            {
                buf = new byte[count];
                Array.Copy(data, offset, buf, 0, count);
            }

            write(masterFd, buf, (IntPtr)buf.Length);
        }

        private void Cleanup()
        {
            running = false;

            if (masterFd >= 0) { close(masterFd); masterFd = -1; }
            if (slaveFd >= 0) { close(slaveFd); slaveFd = -1; }

            // Remove symlink
            if (symlinkPath != null && symlinkPath != slavePath)
            {
                try { File.Delete(symlinkPath); } catch { }
            }
        }

        public void Dispose()
        {
            running = false;
            readThread?.Join(2000);
            Cleanup();
        }
    }
}
