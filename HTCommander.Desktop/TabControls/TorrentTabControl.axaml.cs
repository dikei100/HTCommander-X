/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;

namespace HTCommander.Desktop.TabControls
{
    public class TorrentEntry
    {
        public string FileName { get; set; }
        public string Source { get; set; }
        public string Mode { get; set; }
        public string SizeStr { get; set; }
        public string Progress { get; set; }
    }

    public partial class TorrentTabControl : UserControl
    {
        private DataBrokerClient broker;
        private ObservableCollection<TorrentEntry> torrentEntries = new ObservableCollection<TorrentEntry>();
        private List<int> connectedRadioIds = new List<int>();
        private Dictionary<int, RadioLockState> lockStates = new Dictionary<int, RadioLockState>();
        private bool isActive = false;
        private int activeRadioId = -1;

        public TorrentTabControl()
        {
            InitializeComponent();
            TorrentGrid.ItemsSource = torrentEntries;

            broker = new DataBrokerClient();
            broker.Subscribe(0, "TorrentFiles", OnTorrentFilesUpdate);
            broker.Subscribe(0, "TorrentFileUpdate", OnTorrentFileUpdate);
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);
            broker.Subscribe(DataBroker.AllDevices, "LockState", OnLockStateChanged);

            // Check initial radios
            var radios = broker.GetValue<object>(1, "ConnectedRadios", null);
            if (radios != null) ProcessConnectedRadios(radios);
        }

        private void ProcessConnectedRadios(object data)
        {
            connectedRadioIds.Clear();
            if (data is System.Collections.IEnumerable enumerable)
            {
                foreach (var item in enumerable)
                {
                    if (item == null) continue;
                    int? deviceId = (int?)item.GetType().GetProperty("DeviceId")?.GetValue(item);
                    if (deviceId.HasValue) connectedRadioIds.Add(deviceId.Value);
                }
            }
            UpdateActivateButtonState();
        }

        private void UpdateActivateButtonState()
        {
            bool hasRadios = connectedRadioIds.Count > 0;
            AddFileButton.IsEnabled = hasRadios;

            if (isActive)
            {
                ActivateButton.Content = "Deactivate";
                ActivateButton.IsEnabled = true;
            }
            else
            {
                ActivateButton.Content = "Activate";
                bool canActivate = connectedRadioIds.Any(id =>
                {
                    if (lockStates.TryGetValue(id, out var state))
                        return !state.IsLocked;
                    return true;
                });
                ActivateButton.IsEnabled = canActivate;
            }
        }

        private string FormatSize(int bytes)
        {
            if (bytes < 1024) return $"{bytes} B";
            if (bytes < 1024 * 1024) return $"{bytes / 1024.0:F1} KB";
            return $"{bytes / (1024.0 * 1024.0):F1} MB";
        }

        private void OnTorrentFilesUpdate(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                torrentEntries.Clear();
                if (data is System.Collections.IEnumerable files)
                {
                    foreach (var file in files)
                    {
                        if (file == null) continue;
                        var t = file.GetType();
                        string fileName = t.GetField("FileName")?.GetValue(file) as string ?? "";
                        string callsign = t.GetField("Callsign")?.GetValue(file) as string ?? "";
                        int size = (int)(t.GetField("Size")?.GetValue(file) ?? 0);
                        var mode = t.GetField("Mode")?.GetValue(file);
                        int totalBlocks = (int)(t.GetProperty("TotalBlocks")?.GetValue(file) ?? 0);
                        int receivedBlocks = (int)(t.GetProperty("ReceivedBlocks")?.GetValue(file) ?? 0);

                        string progress = totalBlocks > 0 ? $"{receivedBlocks}/{totalBlocks}" : "";

                        torrentEntries.Add(new TorrentEntry
                        {
                            FileName = fileName,
                            Source = callsign,
                            Mode = mode?.ToString() ?? "",
                            SizeStr = FormatSize(size),
                            Progress = progress
                        });
                    }
                }
            });
        }

        private void OnTorrentFileUpdate(int deviceId, string name, object data)
        {
            // Single file update - refresh all for simplicity
            OnTorrentFilesUpdate(deviceId, name, broker.GetValue<object>(0, "TorrentFiles", null));
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() => ProcessConnectedRadios(data));
        }

        private void OnLockStateChanged(int deviceId, string name, object data)
        {
            Dispatcher.UIThread.Post(() =>
            {
                if (data is RadioLockState state)
                {
                    lockStates[deviceId] = state;
                    if (isActive && deviceId == activeRadioId && (!state.IsLocked || state.Usage != "Torrent"))
                    {
                        isActive = false;
                        activeRadioId = -1;
                        TorrentStatus.Text = "Inactive";
                    }
                    UpdateActivateButtonState();
                }
            });
        }

        private async void AddFileButton_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new Dialogs.AddTorrentFileDialog();
            await dialog.ShowDialog((Window)this.VisualRoot);
            if (!dialog.Confirmed || string.IsNullOrEmpty(dialog.Filename)) return;

            try
            {
                var fileInfo = new System.IO.FileInfo(dialog.Filename);
                if (fileInfo.Length > 10000000) return; // 10MB max

                byte[] fileData = File.ReadAllBytes(dialog.Filename);
                byte[] nameBytes = Encoding.UTF8.GetBytes(fileInfo.Name);
                byte[] data0 = new byte[fileData.Length + nameBytes.Length + 1];
                data0[0] = (byte)nameBytes.Length;
                Array.Copy(nameBytes, 0, data0, 1, nameBytes.Length);
                Array.Copy(fileData, 0, data0, nameBytes.Length + 1, fileData.Length);

                byte[] dataBrotli = Utils.CompressBrotli(data0);
                byte[] dataDeflate = Utils.CompressDeflate(data0);

                var torrentFile = new TorrentFile();
                torrentFile.Completed = true;
                torrentFile.FileName = fileInfo.Name;
                torrentFile.Description = dialog.Description ?? "";
                torrentFile.Description = torrentFile.Description.Substring(0, Math.Min(torrentFile.Description.Length, 200));
                torrentFile.Mode = dialog.Mode == 0 ? TorrentFile.TorrentModes.Sharing : TorrentFile.TorrentModes.Request;
                torrentFile.Size = (int)fileInfo.Length;

                byte[] dataSelected;
                if (dataDeflate.Length < dataBrotli.Length && dataDeflate.Length < data0.Length)
                {
                    torrentFile.Compression = TorrentFile.TorrentCompression.Deflate;
                    torrentFile.CompressedSize = dataDeflate.Length + 1;
                    dataSelected = dataDeflate;
                }
                else if (dataBrotli.Length < dataDeflate.Length && dataBrotli.Length < data0.Length)
                {
                    torrentFile.Compression = TorrentFile.TorrentCompression.Brotli;
                    torrentFile.CompressedSize = dataBrotli.Length + 1;
                    dataSelected = dataBrotli;
                }
                else
                {
                    torrentFile.Compression = TorrentFile.TorrentCompression.None;
                    torrentFile.CompressedSize = data0.Length + 1;
                    dataSelected = data0;
                }

                // Add compression type byte
                byte[] dataWithType = new byte[dataSelected.Length + 1];
                dataWithType[0] = (byte)torrentFile.Compression;
                Array.Copy(dataSelected, 0, dataWithType, 1, dataSelected.Length);

                torrentFile.Id = Utils.ComputeShortSha256Hash(dataWithType);

                // Create blocks
                int blockSize = Torrent.DefaultBlockSize;
                int blockCount = dataWithType.Length / blockSize;
                if ((dataWithType.Length % blockSize) != 0) blockCount++;
                torrentFile.Blocks = new byte[blockCount][];
                for (int i = 0; i < blockCount; i++)
                {
                    int thisBlockSize = Math.Min(blockSize, dataWithType.Length - (i * blockSize));
                    torrentFile.Blocks[i] = new byte[thisBlockSize];
                    Array.Copy(dataWithType, i * blockSize, torrentFile.Blocks[i], 0, thisBlockSize);
                }

                torrentFile.WriteTorrentFile();
                broker.Dispatch(0, "TorrentAddFile", torrentFile, store: false);
            }
            catch (Exception ex)
            {
                DataBroker.Dispatch(1, "LogError", $"[Torrent] Add file error: {ex.Message}", store: false);
            }
        }

        private void ActivateButton_Click(object sender, RoutedEventArgs e)
        {
            if (isActive)
            {
                if (activeRadioId >= 0)
                    broker.Dispatch(activeRadioId, "SetUnlock", new SetUnlockData { Usage = "Torrent" }, store: false);
                isActive = false;
                activeRadioId = -1;
                TorrentStatus.Text = "Inactive";
            }
            else
            {
                int radioId = connectedRadioIds.FirstOrDefault(id =>
                {
                    if (lockStates.TryGetValue(id, out var state))
                        return !state.IsLocked;
                    return true;
                }, -1);

                if (radioId < 0) return;

                broker.Dispatch(radioId, "SetLock", new SetLockData
                {
                    Usage = "Torrent",
                    RegionId = -1,
                    ChannelId = -1
                }, store: false);

                activeRadioId = radioId;
                isActive = true;
                TorrentStatus.Text = "Active";
            }
            UpdateActivateButtonState();
        }
    }
}
