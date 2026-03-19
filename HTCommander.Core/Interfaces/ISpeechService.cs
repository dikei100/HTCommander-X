/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander
{
    /// <summary>
    /// Platform-agnostic text-to-speech service.
    /// Windows: System.Speech, Linux: espeak-ng, Android: Android.Speech.Tts.
    /// </summary>
    public interface ISpeechService
    {
        bool IsAvailable { get; }
        string[] GetVoices();
        void SelectVoice(string voiceName);
        byte[] SynthesizeToWav(string text, int sampleRate);
    }
}
