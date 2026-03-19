/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Runtime.InteropServices;
using SkiaSharp;

namespace HTCommander.SSTV
{
    public class SstvDecodingStartedEventArgs : EventArgs
    {
        public string ModeName { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public class SstvDecodingProgressEventArgs : EventArgs
    {
        public string ModeName { get; set; }
        public int CurrentLine { get; set; }
        public int TotalLines { get; set; }
        public float PercentComplete => TotalLines > 0 ? (CurrentLine / (float)TotalLines) * 100f : 0f;
    }

    public class SstvDecodingCompleteEventArgs : EventArgs
    {
        public string ModeName { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        /// <summary>
        /// The decoded image as an SKBitmap. Caller is responsible for disposing.
        /// </summary>
        public SKBitmap Image { get; set; }
    }

    /// <summary>
    /// Cross-platform SSTV monitor using SkiaSharp instead of System.Drawing.
    /// Wraps the SSTV Decoder to provide event-driven notifications.
    /// </summary>
    public class SstvMonitor : IDisposable
    {
        private Decoder _decoder;
        private PixelBuffer _scopeBuffer;
        private PixelBuffer _imageBuffer;
        private readonly int _sampleRate;
        private readonly object _lock = new object();
        private bool _disposed = false;

        private int _previousLine = -1;
        private bool _isDecoding = false;
        private string _currentModeName = null;
        private int _lastProgressLine = -1;
        private const int ProgressLineInterval = 10;

        public event EventHandler<SstvDecodingStartedEventArgs> DecodingStarted;
        public event EventHandler<SstvDecodingProgressEventArgs> DecodingProgress;
        public event EventHandler<SstvDecodingCompleteEventArgs> DecodingComplete;

        public SstvMonitor(int sampleRate = 32000)
        {
            _sampleRate = sampleRate;
            Initialize();
        }

        private void Initialize()
        {
            _scopeBuffer = new PixelBuffer(800, 616);
            _imageBuffer = new PixelBuffer(800, 616);
            _imageBuffer.Line = -1;
            _decoder = new Decoder(_scopeBuffer, _imageBuffer, "Raw", _sampleRate);
            _previousLine = -1;
            _isDecoding = false;
            _currentModeName = null;
            _lastProgressLine = -1;
        }

        public void Reset()
        {
            lock (_lock) { Initialize(); }
        }

        public void ProcessPcm16(byte[] pcmData, int offset, int length)
        {
            if (_disposed || pcmData == null || length <= 0) return;
            int sampleCount = length / 2;
            float[] samples = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                int byteIndex = offset + i * 2;
                if (byteIndex + 1 >= offset + length) break;
                short sample = (short)(pcmData[byteIndex] | (pcmData[byteIndex + 1] << 8));
                samples[i] = sample / 32768f;
            }
            ProcessFloatSamples(samples);
        }

        public void ProcessFloatSamples(float[] samples)
        {
            if (_disposed || samples == null || samples.Length == 0) return;

            SstvDecodingStartedEventArgs startedArgs = null;
            SstvDecodingProgressEventArgs progressArgs = null;
            SstvDecodingCompleteEventArgs completeArgs = null;

            lock (_lock)
            {
                if (_decoder == null) return;
                bool newLines = _decoder.Process(samples, 0);
                int currentLine = _imageBuffer.Line;
                int height = _imageBuffer.Height;

                if (!_isDecoding && currentLine >= 0 && currentLine < height && _decoder.CurrentMode != null)
                {
                    _isDecoding = true;
                    _currentModeName = _decoder.CurrentMode.GetName();
                    _lastProgressLine = 0;
                    startedArgs = new SstvDecodingStartedEventArgs
                    {
                        ModeName = _currentModeName,
                        Width = _decoder.CurrentMode.GetWidth(),
                        Height = _decoder.CurrentMode.GetHeight()
                    };
                }

                if (_isDecoding && newLines && currentLine > _previousLine && currentLine < height)
                {
                    if (currentLine - _lastProgressLine >= ProgressLineInterval)
                    {
                        _lastProgressLine = currentLine;
                        progressArgs = new SstvDecodingProgressEventArgs
                        {
                            ModeName = _currentModeName,
                            CurrentLine = currentLine,
                            TotalLines = height
                        };
                    }
                }

                if (_isDecoding && currentLine >= height && _previousLine < height)
                {
                    SKBitmap image = ExtractImage();
                    completeArgs = new SstvDecodingCompleteEventArgs
                    {
                        ModeName = _currentModeName,
                        Width = image?.Width ?? 0,
                        Height = image?.Height ?? 0,
                        Image = image
                    };
                    _isDecoding = false;
                    _currentModeName = null;
                    _previousLine = -1;
                    _lastProgressLine = -1;
                    Initialize();
                }
                else
                {
                    _previousLine = currentLine;
                }
            }

            if (startedArgs != null) DecodingStarted?.Invoke(this, startedArgs);
            if (progressArgs != null) DecodingProgress?.Invoke(this, progressArgs);
            if (completeArgs != null) DecodingComplete?.Invoke(this, completeArgs);
        }

        private SKBitmap ExtractImage()
        {
            try
            {
                int width = _imageBuffer.Width;
                int height = _imageBuffer.Height;
                int[] pixels = _imageBuffer.Pixels;

                if (width <= 0 || height <= 0 || pixels == null || pixels.Length < width * height)
                    return null;

                int[] finalPixels = pixels;
                int finalWidth = width;
                int finalHeight = height;

                if (_decoder.CurrentMode != null)
                {
                    finalPixels = _decoder.CurrentMode.PostProcessScopeImage(pixels, width, height);
                    int modeWidth = _decoder.CurrentMode.GetWidth();
                    if (finalPixels.Length != width * height && modeWidth > 0 && finalPixels.Length == modeWidth * height)
                    {
                        finalWidth = modeWidth;
                    }
                }

                return PixelsToSkBitmap(finalPixels, finalWidth, finalHeight);
            }
            catch { return null; }
        }

        public SKBitmap GetPartialImage()
        {
            lock (_lock)
            {
                if (_imageBuffer == null || _imageBuffer.Line <= 0) return null;
                try
                {
                    int width = _imageBuffer.Width;
                    int fullHeight = _imageBuffer.Height;
                    int decodedLines = Math.Min(_imageBuffer.Line, fullHeight);
                    int[] pixels = _imageBuffer.Pixels;

                    if (width <= 0 || fullHeight <= 0 || pixels == null || pixels.Length < width * decodedLines)
                        return null;

                    int totalPixels = width * fullHeight;
                    int[] fullPixels = new int[totalPixels];
                    unchecked
                    {
                        int opaqueBlack = (int)0xFF000000;
                        for (int i = 0; i < totalPixels; i++) { fullPixels[i] = opaqueBlack; }
                    }
                    Array.Copy(pixels, 0, fullPixels, 0, width * decodedLines);

                    return PixelsToSkBitmap(fullPixels, width, fullHeight);
                }
                catch { return null; }
            }
        }

        /// <summary>
        /// Creates an SKBitmap from raw ARGB pixel data.
        /// </summary>
        private static SKBitmap PixelsToSkBitmap(int[] pixels, int width, int height)
        {
            var bitmap = new SKBitmap(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
            var handle = GCHandle.Alloc(pixels, GCHandleType.Pinned);
            try
            {
                bitmap.InstallPixels(
                    new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul),
                    handle.AddrOfPinnedObject(),
                    width * 4);
                // Force copy so we can release the pinned array
                var copy = bitmap.Copy();
                bitmap.Dispose();
                return copy;
            }
            finally
            {
                handle.Free();
            }
        }

        public void Dispose()
        {
            _disposed = true;
            lock (_lock)
            {
                _decoder = null;
                _scopeBuffer = null;
                _imageBuffer = null;
            }
        }
    }
}
