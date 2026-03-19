/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;

namespace HTCommander
{
    /// <summary>
    /// Pure managed audio resampler. Replaces Windows-only MediaFoundationResampler.
    /// Uses linear interpolation — sufficient for speech (32kHz→16kHz for Whisper, etc.).
    /// Works on all platforms: Windows, Linux, Android.
    /// </summary>
    public static class AudioResampler
    {
        /// <summary>
        /// Resample 16-bit mono PCM audio from one sample rate to another.
        /// </summary>
        /// <param name="input">Input PCM samples (16-bit signed, little-endian).</param>
        /// <param name="inputSampleRate">Input sample rate in Hz.</param>
        /// <param name="outputSampleRate">Output sample rate in Hz.</param>
        /// <returns>Resampled PCM samples (16-bit signed, little-endian).</returns>
        public static byte[] Resample16BitMono(byte[] input, int inputSampleRate, int outputSampleRate)
        {
            if (input == null || input.Length < 2) return input;
            if (inputSampleRate == outputSampleRate) return input;

            int inputSamples = input.Length / 2;
            int outputSamples = (int)((long)inputSamples * outputSampleRate / inputSampleRate);
            byte[] output = new byte[outputSamples * 2];

            double ratio = (double)inputSampleRate / outputSampleRate;

            for (int i = 0; i < outputSamples; i++)
            {
                double srcPos = i * ratio;
                int srcIndex = (int)srcPos;
                double frac = srcPos - srcIndex;

                short sample1 = GetSample16(input, srcIndex);
                short sample2 = GetSample16(input, Math.Min(srcIndex + 1, inputSamples - 1));

                // Linear interpolation
                short result = (short)(sample1 + (sample2 - sample1) * frac);

                output[i * 2] = (byte)(result & 0xFF);
                output[i * 2 + 1] = (byte)((result >> 8) & 0xFF);
            }

            return output;
        }

        /// <summary>
        /// Resample 16-bit stereo PCM audio to mono at a different sample rate.
        /// </summary>
        public static byte[] ResampleStereoToMono16Bit(byte[] input, int inputSampleRate, int outputSampleRate)
        {
            if (input == null || input.Length < 4) return input;

            // First convert stereo to mono
            int stereoSamples = input.Length / 4; // 2 bytes per sample, 2 channels
            byte[] mono = new byte[stereoSamples * 2];

            for (int i = 0; i < stereoSamples; i++)
            {
                short left = GetSample16(input, i * 2);
                short right = GetSample16(input, i * 2 + 1);
                short mixed = (short)((left + right) / 2);
                mono[i * 2] = (byte)(mixed & 0xFF);
                mono[i * 2 + 1] = (byte)((mixed >> 8) & 0xFF);
            }

            // Then resample
            return Resample16BitMono(mono, inputSampleRate, outputSampleRate);
        }

        private static short GetSample16(byte[] data, int sampleIndex)
        {
            int byteIndex = sampleIndex * 2;
            if (byteIndex + 1 >= data.Length) return 0;
            return (short)(data[byteIndex] | (data[byteIndex + 1] << 8));
        }
    }
}
