/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;

namespace HTCommander.Platform.Linux
{
    /// <summary>
    /// Linux TTS using espeak-ng. Falls back gracefully if not installed.
    /// </summary>
    public class LinuxSpeechService : ISpeechService
    {
        private string _selectedVoice = null;
        private bool _available;

        public LinuxSpeechService()
        {
            _available = CheckEspeakAvailable();
        }

        public bool IsAvailable => _available;

        public string[] GetVoices()
        {
            if (!_available) return Array.Empty<string>();

            try
            {
                var psi = new ProcessStartInfo("espeak-ng", "--voices")
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var process = Process.Start(psi);
                var voices = new List<string>();
                string line;
                bool headerSkipped = false;

                while ((line = process.StandardOutput.ReadLine()) != null)
                {
                    if (!headerSkipped) { headerSkipped = true; continue; }
                    // Format: "Pty Language  Age/Gender VoiceName   File ..."
                    var parts = line.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length >= 4)
                    {
                        voices.Add(parts[3]); // Voice name
                    }
                }

                process.WaitForExit(5000);
                return voices.ToArray();
            }
            catch (Exception)
            {
                return Array.Empty<string>();
            }
        }

        public void SelectVoice(string voiceName)
        {
            _selectedVoice = voiceName;
        }

        public byte[] SynthesizeToWav(string text, int sampleRate)
        {
            if (!_available) return null;

            try
            {
                string tempFile = Path.GetTempFileName() + ".wav";
                try
                {
                    string voiceArg = _selectedVoice != null ? $"-v {_selectedVoice}" : "";
                    var psi = new ProcessStartInfo("espeak-ng",
                        $"{voiceArg} -s 150 -w \"{tempFile}\" \"{text.Replace("\"", "\\\"")}\""
                    )
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardError = true
                    };

                    using var process = Process.Start(psi);
                    process.WaitForExit(10000);

                    if (File.Exists(tempFile))
                    {
                        return File.ReadAllBytes(tempFile);
                    }
                }
                finally
                {
                    try { File.Delete(tempFile); } catch { }
                }
            }
            catch (Exception) { }

            return null;
        }

        private static bool CheckEspeakAvailable()
        {
            try
            {
                var psi = new ProcessStartInfo("espeak-ng", "--version")
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using var process = Process.Start(psi);
                process.WaitForExit(3000);
                return process.ExitCode == 0;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }
}
