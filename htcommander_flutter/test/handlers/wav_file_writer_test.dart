import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/radio/wav_file_writer.dart';

void main() {
  group('WavFileWriter', () {
    late String tmpPath;

    setUp(() {
      tmpPath =
          '${Directory.systemTemp.path}/test_wav_${DateTime.now().millisecondsSinceEpoch}.wav';
    });

    tearDown(() {
      final f = File(tmpPath);
      if (f.existsSync()) f.deleteSync();
    });

    test('creates valid WAV header', () {
      final writer = WavFileWriter(tmpPath, sampleRate: 32000);
      writer.open();
      writer.close();

      final bytes = File(tmpPath).readAsBytesSync();
      // RIFF header
      expect(String.fromCharCodes(bytes.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(bytes.sublist(8, 12)), equals('WAVE'));
      // fmt chunk
      expect(String.fromCharCodes(bytes.sublist(12, 16)), equals('fmt '));
      // PCM format = 1
      expect(bytes[20] | (bytes[21] << 8), equals(1));
      // Channels = 1
      expect(bytes[22] | (bytes[23] << 8), equals(1));
      // Sample rate = 32000
      expect(
          bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24),
          equals(32000));
      // Bits per sample = 16
      expect(bytes[34] | (bytes[35] << 8), equals(16));
      // data chunk
      expect(String.fromCharCodes(bytes.sublist(36, 40)), equals('data'));
    });

    test('writes PCM data and updates sizes', () {
      final writer = WavFileWriter(tmpPath, sampleRate: 32000);
      writer.open();

      // Write 100 samples (200 bytes)
      final samples = Int16List(100);
      for (var i = 0; i < 100; i++) {
        samples[i] = (i * 100) - 5000;
      }
      writer.writeInt16Samples(samples);
      expect(writer.dataSize, equals(200));
      writer.close();

      final bytes = File(tmpPath).readAsBytesSync();
      // Total file size = 44 header + 200 data
      expect(bytes.length, equals(244));

      // RIFF chunk size = total - 8
      final riffSize =
          bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
      expect(riffSize, equals(236));

      // Data chunk size
      final dataSize = bytes[40] |
          (bytes[41] << 8) |
          (bytes[42] << 16) |
          (bytes[43] << 24);
      expect(dataSize, equals(200));
    });

    test('durationSeconds is correct', () {
      final writer = WavFileWriter(tmpPath, sampleRate: 32000);
      writer.open();
      // 32000 samples * 2 bytes = 64000 bytes = 1 second
      writer.writeSamples(Uint8List(64000));
      expect(writer.durationSeconds, closeTo(1.0, 0.001));
      writer.close();
    });

    test('supports stereo output', () {
      final writer =
          WavFileWriter(tmpPath, sampleRate: 44100, channels: 2);
      writer.open();
      writer.close();

      final bytes = File(tmpPath).readAsBytesSync();
      // Channels = 2
      expect(bytes[22] | (bytes[23] << 8), equals(2));
      // Byte rate = 44100 * 2 * 2 = 176400
      final byteRate =
          bytes[28] | (bytes[29] << 8) | (bytes[30] << 16) | (bytes[31] << 24);
      expect(byteRate, equals(176400));
    });
  });
}
