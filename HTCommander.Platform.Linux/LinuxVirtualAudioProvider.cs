/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// PulseAudio/PipeWire virtual audio device implementation.
    /// Creates null sinks and virtual sources for bidirectional audio routing.
    /// External software sees "HTCommander Radio Audio" as input and "HTCommander TX" as output.
    /// </summary>
    public class LinuxVirtualAudioProvider : IVirtualAudioProvider
    {
        private int rxSinkModuleId = -1;
        private int txSinkModuleId = -1;
        private int virtualSourceModuleId = -1;
        private Process parecordProcess;
        private Process pacatProcess;
        private Thread txReadThread;
        private volatile bool running = false;
        private int sampleRate;

        public string SinkName => "HTCommander TX";
        public string SourceName => "HTCommander Radio Audio";
        public bool IsRunning => running;
        public event Action<byte[], int> TxDataAvailable;

        public bool Create(int sampleRate)
        {
            this.sampleRate = sampleRate;

            try
            {
                // Clean up any stale modules from previous runs
                CleanupStaleModules();

                // Create RX null sink (radio audio goes here)
                rxSinkModuleId = LoadModule(
                    "module-null-sink",
                    $"sink_name=HTCommander_RX sink_properties=device.description=\"HTCommander\\sRX\"");
                if (rxSinkModuleId < 0) return false;

                // Create TX null sink (external software outputs here)
                txSinkModuleId = LoadModule(
                    "module-null-sink",
                    $"sink_name=HTCommander_TX sink_properties=device.description=\"HTCommander\\sTX\"");
                if (txSinkModuleId < 0) { Destroy(); return false; }

                // Create virtual source from RX sink's monitor
                // This is what external software selects as its input device
                virtualSourceModuleId = LoadModule(
                    "module-virtual-source",
                    $"source_name=HTCommander_RX_Source master=HTCommander_RX.monitor source_properties=device.description=\"HTCommander\\sRadio\\sAudio\"");
                if (virtualSourceModuleId < 0) { Destroy(); return false; }

                // Start pacat for writing RX audio to the RX sink
                pacatProcess = new Process();
                pacatProcess.StartInfo = new ProcessStartInfo
                {
                    FileName = "pacat",
                    Arguments = $"--device=HTCommander_RX --format=s16le --rate={sampleRate} --channels=1 --raw --latency-msec=20",
                    UseShellExecute = false,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false,
                    CreateNoWindow = true
                };
                pacatProcess.Start();

                // Start parecord for reading TX audio from the TX sink's monitor
                parecordProcess = new Process();
                parecordProcess.StartInfo = new ProcessStartInfo
                {
                    FileName = "parecord",
                    Arguments = $"--device=HTCommander_TX.monitor --format=s16le --rate={sampleRate} --channels=1 --raw --latency-msec=20",
                    UseShellExecute = false,
                    RedirectStandardInput = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = false,
                    CreateNoWindow = true
                };
                parecordProcess.Start();

                // Start TX read thread
                running = true;
                txReadThread = new Thread(TxReadLoop)
                {
                    IsBackground = true,
                    Name = "VirtualAudioTxRead"
                };
                txReadThread.Start();

                return true;
            }
            catch
            {
                Destroy();
                return false;
            }
        }

        public void WriteSamples(byte[] pcm, int offset, int count)
        {
            if (!running || pacatProcess == null || pacatProcess.HasExited) return;

            try
            {
                var stdin = pacatProcess.StandardInput.BaseStream;
                stdin.Write(pcm, offset, count);
                stdin.Flush();
            }
            catch { }
        }

        private void TxReadLoop()
        {
            byte[] buffer = new byte[9600]; // ~100ms at 48kHz mono 16-bit

            try
            {
                var stdout = parecordProcess.StandardOutput.BaseStream;

                while (running && !parecordProcess.HasExited)
                {
                    int bytesRead = stdout.Read(buffer, 0, buffer.Length);
                    if (bytesRead <= 0) break;

                    // Check if the data is silence (all zeros) — skip to avoid unnecessary processing
                    bool isSilence = true;
                    for (int i = 0; i < bytesRead; i += 64)
                    {
                        if (buffer[i] != 0 || (i + 1 < bytesRead && buffer[i + 1] != 0))
                        {
                            isSilence = false;
                            break;
                        }
                    }
                    if (isSilence) continue;

                    byte[] data = new byte[bytesRead];
                    Array.Copy(buffer, data, bytesRead);
                    TxDataAvailable?.Invoke(data, bytesRead);
                }
            }
            catch { }
        }

        public void Destroy()
        {
            running = false;

            // Stop processes
            try { pacatProcess?.StandardInput?.Close(); } catch { }
            try
            {
                if (pacatProcess != null && !pacatProcess.HasExited)
                {
                    pacatProcess.Kill();
                    pacatProcess.WaitForExit(2000);
                }
            }
            catch { }
            pacatProcess?.Dispose();
            pacatProcess = null;

            try
            {
                if (parecordProcess != null && !parecordProcess.HasExited)
                {
                    parecordProcess.Kill();
                    parecordProcess.WaitForExit(2000);
                }
            }
            catch { }
            parecordProcess?.Dispose();
            parecordProcess = null;

            txReadThread?.Join(2000);
            txReadThread = null;

            // Unload PulseAudio modules
            if (virtualSourceModuleId >= 0)
            {
                UnloadModule(virtualSourceModuleId);
                virtualSourceModuleId = -1;
            }
            if (txSinkModuleId >= 0)
            {
                UnloadModule(txSinkModuleId);
                txSinkModuleId = -1;
            }
            if (rxSinkModuleId >= 0)
            {
                UnloadModule(rxSinkModuleId);
                rxSinkModuleId = -1;
            }
        }

        private void CleanupStaleModules()
        {
            // List loaded modules and remove any HTCommander ones from previous runs
            try
            {
                var process = Process.Start(new ProcessStartInfo
                {
                    FileName = "pactl",
                    Arguments = "list short modules",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                });
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit(5000);

                foreach (string line in output.Split('\n'))
                {
                    if (line.Contains("HTCommander"))
                    {
                        string[] parts = line.Split('\t', ' ');
                        if (parts.Length > 0 && int.TryParse(parts[0], out int moduleId))
                        {
                            UnloadModule(moduleId);
                        }
                    }
                }
            }
            catch { }
        }

        private int LoadModule(string moduleName, string arguments)
        {
            try
            {
                var process = Process.Start(new ProcessStartInfo
                {
                    FileName = "pactl",
                    Arguments = $"load-module {moduleName} {arguments}",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                });
                string output = process.StandardOutput.ReadToEnd().Trim();
                process.WaitForExit(5000);

                if (process.ExitCode == 0 && int.TryParse(output, out int moduleId))
                {
                    return moduleId;
                }
            }
            catch { }
            return -1;
        }

        private void UnloadModule(int moduleId)
        {
            try
            {
                var process = Process.Start(new ProcessStartInfo
                {
                    FileName = "pactl",
                    Arguments = $"unload-module {moduleId}",
                    UseShellExecute = false,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false,
                    CreateNoWindow = true
                });
                process.WaitForExit(3000);
            }
            catch { }
        }

        public void Dispose()
        {
            Destroy();
        }
    }
}
