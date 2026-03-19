/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Interface for speech-to-text engine (Whisper or platform equivalent).
    /// Mirrors the WhisperEngine API used by VoiceHandler.
    /// </summary>
    public interface IWhisperEngine : IDisposable
    {
        void StartVoiceSegment();
        void CompleteVoiceSegment();
        void ResetVoiceSegment();
        void ProcessAudioChunk(byte[] data, int offset, int length, string channelName);

        event Action<string> OnDebugMessage;
        event Action<bool> onProcessingVoice;
        event Action<string, string, DateTime, bool> onTextReady;
    }
}
