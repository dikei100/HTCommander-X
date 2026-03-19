/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using SkiaSharp;

namespace HTCommander
{
    /// <summary>
    /// Conversion helpers between SKBitmap (SkiaSharp) and System.Drawing.Bitmap.
    /// Only available in the WinForms project.
    /// </summary>
    public static class SkiaBitmapConverter
    {
        /// <summary>
        /// Convert an SKBitmap to a System.Drawing.Bitmap.
        /// </summary>
        public static Bitmap ToDrawingBitmap(SKBitmap skBitmap)
        {
            if (skBitmap == null) return null;

            using (var image = SKImage.FromBitmap(skBitmap))
            using (var data = image.Encode(SKEncodedImageFormat.Png, 100))
            using (var stream = new MemoryStream(data.ToArray()))
            {
                return new Bitmap(stream);
            }
        }

        /// <summary>
        /// Convert a System.Drawing.Bitmap to an SKBitmap.
        /// </summary>
        public static SKBitmap ToSkBitmap(Bitmap bitmap)
        {
            if (bitmap == null) return null;

            using (var stream = new MemoryStream())
            {
                bitmap.Save(stream, ImageFormat.Png);
                stream.Position = 0;
                return SKBitmap.Decode(stream);
            }
        }
    }
}
