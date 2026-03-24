import 'dart:io';
import 'dart:typed_data';

/// Writes PCM audio data to a WAV file.
///
/// Supports mono 16-bit PCM at any sample rate.
class WavFileWriter {
  final File _file;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  RandomAccessFile? _raf;
  int _dataSize = 0;

  WavFileWriter(
    String path, {
    this.sampleRate = 32000,
    this.channels = 1,
    this.bitsPerSample = 16,
  }) : _file = File(path);

  /// Opens the file and writes the WAV header placeholder.
  void open() {
    _raf = _file.openSync(mode: FileMode.write);
    _dataSize = 0;
    _writeHeader();
  }

  /// Writes PCM samples to the file.
  void writeSamples(Uint8List pcmData) {
    final raf = _raf;
    if (raf == null) return;
    raf.writeFromSync(pcmData);
    _dataSize += pcmData.length;
  }

  /// Writes Int16List samples to the file as little-endian bytes.
  void writeInt16Samples(Int16List samples) {
    writeSamples(Uint8List.view(samples.buffer, samples.offsetInBytes,
        samples.lengthInBytes));
  }

  /// Finalizes the WAV file by updating the header with actual sizes.
  void close() {
    final raf = _raf;
    if (raf == null) return;

    // Update RIFF chunk size
    raf.setPositionSync(4);
    _writeUint32LE(raf, 36 + _dataSize);

    // Update data chunk size
    raf.setPositionSync(40);
    _writeUint32LE(raf, _dataSize);

    raf.closeSync();
    _raf = null;
  }

  /// Returns the path of the WAV file.
  String get path => _file.path;

  /// Returns the number of data bytes written so far.
  int get dataSize => _dataSize;

  /// Returns the duration in seconds of audio written so far.
  double get durationSeconds {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    if (byteRate == 0) return 0;
    return _dataSize / byteRate;
  }

  void _writeHeader() {
    final raf = _raf!;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);

    // RIFF header
    raf.writeStringSync('RIFF');
    _writeUint32LE(raf, 36); // placeholder, updated on close
    raf.writeStringSync('WAVE');

    // fmt chunk
    raf.writeStringSync('fmt ');
    _writeUint32LE(raf, 16); // chunk size
    _writeUint16LE(raf, 1); // PCM format
    _writeUint16LE(raf, channels);
    _writeUint32LE(raf, sampleRate);
    _writeUint32LE(raf, byteRate);
    _writeUint16LE(raf, blockAlign);
    _writeUint16LE(raf, bitsPerSample);

    // data chunk
    raf.writeStringSync('data');
    _writeUint32LE(raf, 0); // placeholder, updated on close
  }

  static void _writeUint16LE(RandomAccessFile raf, int value) {
    raf.writeByteSync(value & 0xFF);
    raf.writeByteSync((value >> 8) & 0xFF);
  }

  static void _writeUint32LE(RandomAccessFile raf, int value) {
    raf.writeByteSync(value & 0xFF);
    raf.writeByteSync((value >> 8) & 0xFF);
    raf.writeByteSync((value >> 16) & 0xFF);
    raf.writeByteSync((value >> 24) & 0xFF);
  }
}
