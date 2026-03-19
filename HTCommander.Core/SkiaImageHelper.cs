/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using SkiaSharp;

namespace HTCommander
{
    /// <summary>
    /// Cross-platform image helper using SkiaSharp.
    /// Replaces System.Drawing.Bitmap usage for image operations.
    /// </summary>
    public static class SkiaImageHelper
    {
        /// <summary>
        /// Load an image from a file path.
        /// </summary>
        public static SKBitmap LoadImage(string path)
        {
            using (var stream = File.OpenRead(path))
            {
                return SKBitmap.Decode(stream);
            }
        }

        /// <summary>
        /// Save an SKBitmap to a file (PNG format).
        /// </summary>
        public static void SavePng(SKBitmap bitmap, string path)
        {
            using (var image = SKImage.FromBitmap(bitmap))
            using (var data = image.Encode(SKEncodedImageFormat.Png, 100))
            using (var stream = File.OpenWrite(path))
            {
                data.SaveTo(stream);
            }
        }

        /// <summary>
        /// Save an SKBitmap to a file (JPEG format).
        /// </summary>
        public static void SaveJpeg(SKBitmap bitmap, string path, int quality = 90)
        {
            using (var image = SKImage.FromBitmap(bitmap))
            using (var data = image.Encode(SKEncodedImageFormat.Jpeg, quality))
            using (var stream = File.OpenWrite(path))
            {
                data.SaveTo(stream);
            }
        }

        /// <summary>
        /// Convert an SKBitmap to PNG byte array.
        /// </summary>
        public static byte[] ToPngBytes(SKBitmap bitmap)
        {
            using (var image = SKImage.FromBitmap(bitmap))
            using (var data = image.Encode(SKEncodedImageFormat.Png, 100))
            {
                return data.ToArray();
            }
        }

        /// <summary>
        /// Create an SKBitmap from raw BGRA pixel data.
        /// </summary>
        public static SKBitmap FromPixels(int[] pixels, int width, int height)
        {
            var bitmap = new SKBitmap(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
            unsafe
            {
                fixed (int* ptr = pixels)
                {
                    bitmap.InstallPixels(
                        new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul),
                        (IntPtr)ptr, width * 4);
                    var copy = bitmap.Copy();
                    bitmap.Dispose();
                    return copy;
                }
            }
        }

        /// <summary>
        /// Resize an image to fit within the specified dimensions while preserving aspect ratio.
        /// </summary>
        public static SKBitmap ResizeToFit(SKBitmap source, int maxWidth, int maxHeight)
        {
            float ratioX = (float)maxWidth / source.Width;
            float ratioY = (float)maxHeight / source.Height;
            float ratio = Math.Min(ratioX, ratioY);

            int newWidth = (int)(source.Width * ratio);
            int newHeight = (int)(source.Height * ratio);

            return source.Resize(new SKImageInfo(newWidth, newHeight), SKFilterQuality.High);
        }
    }
}
