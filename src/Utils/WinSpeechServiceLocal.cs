/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO;
using System.Linq;
using System.Speech.Synthesis;

namespace HTCommander
{
    /// <summary>
    /// Windows TTS service for the WinForms project using System.Speech.
    /// Used by VoiceHandler for text-to-speech.
    /// </summary>
    public class WinSpeechServiceLocal : ISpeechService
    {
        private SpeechSynthesizer synthesizer;

        public WinSpeechServiceLocal()
        {
            try { synthesizer = new SpeechSynthesizer(); }
            catch { synthesizer = null; }
        }

        public bool IsAvailable => synthesizer != null;

        public string[] GetVoices()
        {
            if (synthesizer == null) return Array.Empty<string>();
            return synthesizer.GetInstalledVoices()
                .Where(v => v.Enabled)
                .Select(v => v.VoiceInfo.Name)
                .ToArray();
        }

        public void SelectVoice(string voiceName)
        {
            if (synthesizer == null) return;
            try { synthesizer.SelectVoice(voiceName); } catch { }
        }

        public byte[] SynthesizeToWav(string text, int sampleRate)
        {
            if (synthesizer == null) return null;
            using (var ms = new MemoryStream())
            {
                synthesizer.SetOutputToWaveStream(ms);
                synthesizer.Speak(text);
                synthesizer.SetOutputToNull();
                return ms.ToArray();
            }
        }
    }
}
