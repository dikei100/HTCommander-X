/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;

namespace HTCommander
{
    /// <summary>
    /// Simple cross-platform WAV file writer. Replaces NAudio.Wave.WaveFileWriter
    /// for recording PCM audio to disk. Supports 16-bit PCM only.
    /// </summary>
    public class WavFileWriter : IDisposable
    {
        private readonly FileStream _stream;
        private readonly BinaryWriter _writer;
        private readonly int _sampleRate;
        private readonly int _bitsPerSample;
        private readonly int _channels;
        private long _dataChunkSizePosition;
        private int _dataSize = 0;
        private bool _disposed = false;

        public WavFileWriter(string path, int sampleRate, int bitsPerSample, int channels)
        {
            _sampleRate = sampleRate;
            _bitsPerSample = bitsPerSample;
            _channels = channels;
            _stream = new FileStream(path, FileMode.Create, FileAccess.Write);
            _writer = new BinaryWriter(_stream);
            WriteHeader();
        }

        private void WriteHeader()
        {
            int byteRate = _sampleRate * _channels * (_bitsPerSample / 8);
            short blockAlign = (short)(_channels * (_bitsPerSample / 8));

            // RIFF header
            _writer.Write(new char[] { 'R', 'I', 'F', 'F' });
            _writer.Write(0); // Placeholder for file size - 8
            _writer.Write(new char[] { 'W', 'A', 'V', 'E' });

            // fmt chunk
            _writer.Write(new char[] { 'f', 'm', 't', ' ' });
            _writer.Write(16); // Chunk size
            _writer.Write((short)1); // PCM format
            _writer.Write((short)_channels);
            _writer.Write(_sampleRate);
            _writer.Write(byteRate);
            _writer.Write(blockAlign);
            _writer.Write((short)_bitsPerSample);

            // data chunk
            _writer.Write(new char[] { 'd', 'a', 't', 'a' });
            _dataChunkSizePosition = _stream.Position;
            _writer.Write(0); // Placeholder for data size
        }

        public long Length => _dataSize;

        public void Write(byte[] buffer, int offset, int count)
        {
            if (_disposed) return;
            _writer.Write(buffer, offset, count);
            _dataSize += count;
        }

        public void Flush()
        {
            if (_disposed) return;
            _writer.Flush();
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            try
            {
                // Update data chunk size
                _stream.Position = _dataChunkSizePosition;
                _writer.Write(_dataSize);

                // Update RIFF chunk size (file size - 8)
                _stream.Position = 4;
                _writer.Write((int)(_stream.Length - 8));

                _writer.Flush();
            }
            catch (Exception) { }

            _writer.Dispose();
            _stream.Dispose();
        }
    }
}
