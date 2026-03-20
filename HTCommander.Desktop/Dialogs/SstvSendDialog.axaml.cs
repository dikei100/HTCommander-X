using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using SkiaSharp;

namespace HTCommander.Desktop.Dialogs
{
    public class SstvModeInfo
    {
        public string Name { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int TransmitSeconds { get; set; }
        public override string ToString() => Name;

        public static readonly SstvModeInfo[] AllModes = new SstvModeInfo[]
        {
            new SstvModeInfo { Name = "Robot 36 Color",      Width = 320, Height = 240, TransmitSeconds = 36 },
            new SstvModeInfo { Name = "Robot 72 Color",      Width = 320, Height = 240, TransmitSeconds = 73 },
            new SstvModeInfo { Name = "Martin 1",            Width = 320, Height = 256, TransmitSeconds = 115 },
            new SstvModeInfo { Name = "Martin 2",            Width = 320, Height = 256, TransmitSeconds = 59 },
            new SstvModeInfo { Name = "Scottie 1",           Width = 320, Height = 256, TransmitSeconds = 110 },
            new SstvModeInfo { Name = "Scottie 2",           Width = 320, Height = 256, TransmitSeconds = 72 },
            new SstvModeInfo { Name = "Scottie DX",          Width = 320, Height = 256, TransmitSeconds = 270 },
            new SstvModeInfo { Name = "Wraase SC2\u2013180", Width = 320, Height = 256, TransmitSeconds = 183 },
            new SstvModeInfo { Name = "PD 50",               Width = 320, Height = 256, TransmitSeconds = 51 },
            new SstvModeInfo { Name = "PD 90",               Width = 320, Height = 256, TransmitSeconds = 91 },
            new SstvModeInfo { Name = "PD 120",              Width = 640, Height = 496, TransmitSeconds = 127 },
            new SstvModeInfo { Name = "PD 160",              Width = 512, Height = 400, TransmitSeconds = 162 },
            new SstvModeInfo { Name = "PD 180",              Width = 640, Height = 496, TransmitSeconds = 188 },
            new SstvModeInfo { Name = "PD 240",              Width = 640, Height = 496, TransmitSeconds = 249 },
            new SstvModeInfo { Name = "PD 290",              Width = 800, Height = 616, TransmitSeconds = 290 },
        };
    }

    public partial class SstvSendDialog : Window
    {
        public string SelectedModeName { get; private set; }
        public SKBitmap ScaledBitmap { get; private set; }
        public bool SendRequested { get; private set; }

        private SKBitmap originalBitmap;

        public SstvSendDialog()
        {
            InitializeComponent();
            ModeCombo.ItemsSource = SstvModeInfo.AllModes;
            ModeCombo.SelectedIndex = 0;
            UpdateModeInfo();
        }

        private SstvModeInfo SelectedMode =>
            ModeCombo.SelectedItem as SstvModeInfo;

        private void ModeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            UpdateModeInfo();
            UpdatePreview();
        }

        private void UpdateModeInfo()
        {
            var mode = SelectedMode;
            if (mode != null)
                ModeInfoText.Text = $"{mode.Width} x {mode.Height}, ~{mode.TransmitSeconds}s";
        }

        private async void SelectImage_Click(object sender, RoutedEventArgs e)
        {
            var platform = Program.PlatformServices;
            if (platform?.FilePicker == null) return;

            string path = await platform.FilePicker.PickFileAsync("Select Image",
                new[] { "Image Files|*.png;*.jpg;*.jpeg;*.bmp", "All Files|*.*" });

            if (path != null)
            {
                ImagePath.Text = Path.GetFileName(path);

                try
                {
                    originalBitmap?.Dispose();
                    originalBitmap = SKBitmap.Decode(path);
                    UpdatePreview();
                }
                catch (Exception) { }
            }
        }

        private void UpdatePreview()
        {
            if (originalBitmap == null || SelectedMode == null) return;

            var mode = SelectedMode;
            ScaledBitmap?.Dispose();
            ScaledBitmap = ScaleImageToFill(originalBitmap, mode.Width, mode.Height);
            SelectedModeName = mode.Name;
            SendButton.IsEnabled = true;

            // Convert SKBitmap to Avalonia Bitmap for preview
            try
            {
                using (var data = ScaledBitmap.Encode(SKEncodedImageFormat.Png, 90))
                using (var stream = new MemoryStream(data.ToArray()))
                {
                    PreviewImage.Source = new Bitmap(stream);
                }
            }
            catch (Exception) { }
        }

        private static SKBitmap ScaleImageToFill(SKBitmap source, int targetW, int targetH)
        {
            // Center-crop and scale to fill target dimensions
            float scaleX = (float)targetW / source.Width;
            float scaleY = (float)targetH / source.Height;
            float scale = Math.Max(scaleX, scaleY);

            int srcW = (int)(targetW / scale);
            int srcH = (int)(targetH / scale);
            int srcX = (source.Width - srcW) / 2;
            int srcY = (source.Height - srcH) / 2;

            var cropRect = new SKRectI(srcX, srcY, srcX + srcW, srcY + srcH);
            var cropped = new SKBitmap(srcW, srcH);
            source.ExtractSubset(cropped, cropRect);

            var result = new SKBitmap(targetW, targetH);
            using (var canvas = new SKCanvas(result))
            {
                canvas.DrawBitmap(cropped, new SKRect(0, 0, targetW, targetH),
                    new SKPaint { FilterQuality = SKFilterQuality.High });
            }
            cropped.Dispose();

            // Ensure BGRA8888 format for pixel extraction
            if (result.ColorType != SKColorType.Bgra8888)
            {
                var converted = new SKBitmap(targetW, targetH, SKColorType.Bgra8888, SKAlphaType.Premul);
                using (var canvas = new SKCanvas(converted))
                {
                    canvas.DrawBitmap(result, 0, 0);
                }
                result.Dispose();
                return converted;
            }

            return result;
        }

        private void SendButton_Click(object sender, RoutedEventArgs e)
        {
            if (ScaledBitmap == null || SelectedMode == null) return;
            SelectedModeName = SelectedMode.Name;
            SendRequested = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();

        protected override void OnClosed(EventArgs e)
        {
            if (!SendRequested)
            {
                ScaledBitmap?.Dispose();
                ScaledBitmap = null;
            }
            originalBitmap?.Dispose();
            base.OnClosed(e);
        }
    }
}
