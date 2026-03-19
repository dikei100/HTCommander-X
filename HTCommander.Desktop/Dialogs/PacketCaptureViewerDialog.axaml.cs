using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace HTCommander.Desktop.Dialogs
{
    public partial class PacketCaptureViewerDialog : Window
    {
        private string filename;
        private ObservableCollection<PacketEntry> packets = new ObservableCollection<PacketEntry>();

        public PacketCaptureViewerDialog()
        {
            InitializeComponent();
        }

        public PacketCaptureViewerDialog(string filename)
        {
            InitializeComponent();
            this.filename = filename;
            Title = $"Packet Capture Viewer - {Path.GetFileName(filename)}";
            PacketGrid.ItemsSource = packets;
        }

        protected override void OnOpened(EventArgs e)
        {
            base.OnOpened(e);
            LoadPackets();
        }

        private void LoadPackets()
        {
            try
            {
                if (!File.Exists(filename)) return;
                using var stream = File.OpenRead(filename);
                using var reader = new BinaryReader(stream);

                // Read pcap global header (24 bytes)
                if (stream.Length < 24) return;
                uint magic = reader.ReadUInt32();
                bool swapped = (magic == 0xD4C3B2A1);
                if (magic != 0xA1B2C3D4 && magic != 0xD4C3B2A1) return;
                reader.ReadUInt16(); // version major
                reader.ReadUInt16(); // version minor
                reader.ReadInt32();  // thiszone
                reader.ReadUInt32(); // sigfigs
                reader.ReadUInt32(); // snaplen
                reader.ReadUInt32(); // network

                // Read packets
                while (stream.Position < stream.Length - 16)
                {
                    uint tsSec = reader.ReadUInt32();
                    uint tsUsec = reader.ReadUInt32();
                    uint inclLen = reader.ReadUInt32();
                    uint origLen = reader.ReadUInt32();

                    if (swapped)
                    {
                        tsSec = SwapBytes(tsSec);
                        tsUsec = SwapBytes(tsUsec);
                        inclLen = SwapBytes(inclLen);
                        origLen = SwapBytes(origLen);
                    }

                    if (inclLen > 65535 || stream.Position + inclLen > stream.Length) break;

                    byte[] data = reader.ReadBytes((int)inclLen);
                    var timestamp = DateTimeOffset.FromUnixTimeSeconds(tsSec).AddMicroseconds(tsUsec);

                    packets.Add(new PacketEntry
                    {
                        Time = timestamp.LocalDateTime.ToString("HH:mm:ss.fff"),
                        Channel = "-",
                        Data = BitConverter.ToString(data, 0, Math.Min(data.Length, 32)).Replace("-", " "),
                        RawData = data
                    });
                }
            }
            catch (Exception) { }
        }

        private static uint SwapBytes(uint val)
        {
            return ((val & 0x000000FF) << 24) |
                   ((val & 0x0000FF00) << 8) |
                   ((val & 0x00FF0000) >> 8) |
                   ((val & 0xFF000000) >> 24);
        }

        private void PacketGrid_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (PacketGrid.SelectedItem is PacketEntry entry && entry.RawData != null)
            {
                DecodeBox.Text = FormatHexDump(entry.RawData);
            }
            else
            {
                DecodeBox.Text = string.Empty;
            }
        }

        private static string FormatHexDump(byte[] data)
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < data.Length; i += 16)
            {
                sb.Append($"{i:X4}  ");
                for (int j = 0; j < 16; j++)
                {
                    if (i + j < data.Length)
                        sb.Append($"{data[i + j]:X2} ");
                    else
                        sb.Append("   ");
                    if (j == 7) sb.Append(' ');
                }
                sb.Append(" ");
                for (int j = 0; j < 16 && i + j < data.Length; j++)
                {
                    byte b = data[i + j];
                    sb.Append(b >= 32 && b < 127 ? (char)b : '.');
                }
                sb.AppendLine();
            }
            return sb.ToString();
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
    }

    public class PacketEntry
    {
        public string Time { get; set; }
        public string Channel { get; set; }
        public string Data { get; set; }
        public byte[] RawData { get; set; }
    }
}
