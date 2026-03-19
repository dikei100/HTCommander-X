/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Encoding type for voice text entries.
    /// </summary>
    public enum VoiceTextEncodingType
    {
        Voice, Morse, VoiceClip, AX25, BSS, Recording, Picture, APRS, Ident
    }

    /// <summary>
    /// Represents a voice text entry (received or transmitted).
    /// </summary>
    public class DecodedTextEntry
    {
        public string Text { get; set; }
        public string Channel { get; set; }
        public DateTime Time { get; set; }
        public bool IsReceived { get; set; } = true;
        public VoiceTextEncodingType Encoding { get; set; } = VoiceTextEncodingType.Voice;
        public string Source { get; set; }
        public string Destination { get; set; }
        public double Latitude { get; set; } = 0;
        public double Longitude { get; set; } = 0;
        public string Filename { get; set; }
        public int Duration { get; set; } = 0;
    }
}
