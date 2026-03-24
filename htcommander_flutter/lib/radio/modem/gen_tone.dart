/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// NCO tone generator for AFSK / PSK / baseband modulation.
/// Simplified port of HTCommander.Core/hamlib/GenTone.cs adapted for the
/// Flutter software-modem pipeline where audio is collected into a sample
/// list rather than pushed into a multi-channel audio buffer.
library;

import 'dart:math';
import 'dart:typed_data';

/// Modem type for tone generation.
enum GenToneModemType {
  afsk,
  qpsk,
  psk8,
  baseband,
  scramble,
}

/// Numerically-controlled oscillator that generates 16-bit PCM samples for
/// various modem types.
class GenTone {
  static const double _ticksPerCycle = 256.0 * 256.0 * 256.0 * 256.0;
  static const int _phaseShift180 = 128 << 24;
  static const int _phaseShift90 = 64 << 24;
  static const int _phaseShift45 = 32 << 24;

  final Int16List _sineTable = Int16List(256);

  int _ticksPerSample = 0;
  int _ticksPerBit = 0;
  int _f1ChangePerSample = 0;
  int _f2ChangePerSample = 0;

  int _tonePhase = 0;
  int _bitLenAcc = 0;
  int _lfsr = 0;
  int _bitCount = 0;
  int _saveBit = 0;
  int _prevDat = 0;

  GenToneModemType _modemType = GenToneModemType.afsk;

  /// Output sample buffer -- call [drainSamples] to collect generated audio.
  final List<int> _samples = [];

  /// Initialize the tone generator.
  ///
  /// [sampleRate] - Audio sample rate in Hz
  /// [baud]       - Symbol rate
  /// [markFreq]   - Mark tone frequency (Hz)
  /// [spaceFreq]  - Space tone frequency (Hz)
  /// [amp]        - Amplitude percentage (0-100)
  /// [modemType]  - Modulation type
  void init({
    required int sampleRate,
    required int baud,
    int markFreq = 1200,
    int spaceFreq = 2200,
    int amp = 50,
    GenToneModemType modemType = GenToneModemType.afsk,
  }) {
    _modemType = modemType;
    _tonePhase = 0;
    _bitLenAcc = 0;
    _lfsr = 0;
    _bitCount = 0;
    _saveBit = 0;
    _prevDat = 0;

    _ticksPerSample =
        (_ticksPerCycle / sampleRate + 0.5).toInt() & 0xFFFFFFFF;

    switch (modemType) {
      case GenToneModemType.qpsk:
        _ticksPerBit =
            (_ticksPerCycle / (baud * 0.5) + 0.5).toInt() & 0xFFFFFFFF;
        _f1ChangePerSample =
            (markFreq * _ticksPerCycle / sampleRate + 0.5).toInt() &
                0xFFFFFFFF;
        _f2ChangePerSample = _f1ChangePerSample;
        _tonePhase = _phaseShift45;
        break;

      case GenToneModemType.psk8:
        _ticksPerBit =
            (_ticksPerCycle / (baud / 3.0) + 0.5).toInt() & 0xFFFFFFFF;
        _f1ChangePerSample =
            (markFreq * _ticksPerCycle / sampleRate + 0.5).toInt() &
                0xFFFFFFFF;
        _f2ChangePerSample = _f1ChangePerSample;
        break;

      case GenToneModemType.baseband:
      case GenToneModemType.scramble:
        _ticksPerBit =
            (_ticksPerCycle / baud + 0.5).toInt() & 0xFFFFFFFF;
        _f1ChangePerSample =
            (baud * 0.5 * _ticksPerCycle / sampleRate + 0.5).toInt() &
                0xFFFFFFFF;
        break;

      case GenToneModemType.afsk:
        _ticksPerBit =
            (_ticksPerCycle / baud + 0.5).toInt() & 0xFFFFFFFF;
        _f1ChangePerSample =
            (markFreq * _ticksPerCycle / sampleRate + 0.5).toInt() &
                0xFFFFFFFF;
        _f2ChangePerSample =
            (spaceFreq * _ticksPerCycle / sampleRate + 0.5).toInt() &
                0xFFFFFFFF;
        break;
    }

    // Generate sine table.
    for (int j = 0; j < 256; j++) {
      final double a = (j / 256.0) * (2 * pi);
      int s = (sin(a) * 32767 * amp / 100.0).toInt();
      if (s < -32768) s = -32768;
      if (s > 32767) s = 32767;
      _sineTable[j] = s;
    }
  }

  /// Generate tone for one data bit.
  void putBit(int dat) {
    if (dat < 0) {
      _bitLenAcc =
          (_bitLenAcc - _ticksPerBit) & 0xFFFFFFFF;
      dat = 0;
    }

    // Handle multi-bit symbols for QPSK.
    if (_modemType == GenToneModemType.qpsk) {
      dat &= 1;
      if ((_bitCount & 1) == 0) {
        _saveBit = dat;
        _bitCount++;
        return;
      }
      final int dibit = (_saveBit << 1) | dat;
      const gray2phase = [0, 1, 3, 2];
      final int symbol = gray2phase[dibit];
      _tonePhase =
          (_tonePhase + symbol * _phaseShift90) & 0xFFFFFFFF;
      _bitCount++;
    } else if (_modemType == GenToneModemType.psk8) {
      dat &= 1;
      if (_bitCount < 2) {
        _saveBit = (_saveBit << 1) | dat;
        _bitCount++;
        return;
      }
      final int tribit = (_saveBit << 1) | dat;
      const gray2phase = [1, 0, 2, 3, 6, 7, 5, 4];
      final int symbol = gray2phase[tribit];
      _tonePhase =
          (_tonePhase + symbol * _phaseShift45) & 0xFFFFFFFF;
      _saveBit = 0;
      _bitCount = 0;
    }

    // Scrambler for G3RUH.
    if (_modemType == GenToneModemType.scramble) {
      final int x =
          (dat ^ (_lfsr >> 16) ^ (_lfsr >> 11)) & 1;
      _lfsr = ((_lfsr << 1) | (x & 1)) & 0x1FFFF;
      dat = x;
    }

    // Generate audio samples for this bit.
    do {
      int sam;
      switch (_modemType) {
        case GenToneModemType.afsk:
          _tonePhase = (_tonePhase +
                  (dat != 0
                      ? _f1ChangePerSample
                      : _f2ChangePerSample)) &
              0xFFFFFFFF;
          sam = _sineTable[(_tonePhase >> 24) & 0xFF];
          _putSample(sam);
          break;

        case GenToneModemType.qpsk:
        case GenToneModemType.psk8:
          _tonePhase =
              (_tonePhase + _f1ChangePerSample) & 0xFFFFFFFF;
          sam = _sineTable[(_tonePhase >> 24) & 0xFF];
          _putSample(sam);
          break;

        case GenToneModemType.baseband:
        case GenToneModemType.scramble:
          if (dat != _prevDat) {
            _tonePhase =
                (_tonePhase + _f1ChangePerSample) & 0xFFFFFFFF;
          } else {
            if ((_tonePhase & 0x80000000) != 0) {
              _tonePhase = 0xC0000000; // 270 degrees
            } else {
              _tonePhase = 0x40000000; // 90 degrees
            }
          }
          sam = _sineTable[(_tonePhase >> 24) & 0xFF];
          _putSample(sam);
          break;
      }

      _bitLenAcc =
          (_bitLenAcc + _ticksPerSample) & 0xFFFFFFFF;
    } while (_toSigned32(_bitLenAcc) < _toSigned32(_ticksPerBit));

    _bitLenAcc =
        (_bitLenAcc - _ticksPerBit) & 0xFFFFFFFF;
    _prevDat = dat;
  }

  /// Generate a quiet period of [timeMs] milliseconds.
  void putQuietMs(int timeMs, int sampleRate) {
    final int nsamples =
        (timeMs * sampleRate / 1000.0 + 0.5).toInt();
    for (int j = 0; j < nsamples; j++) {
      _putSample(0);
    }
    _tonePhase = 0;
  }

  void _putSample(int sample) {
    if (sample < -32768) sample = -32768;
    if (sample > 32767) sample = 32767;
    _samples.add(sample);
  }

  /// Drain all generated samples into a 16-bit little-endian PCM byte array.
  Uint8List drainSamples() {
    final pcm = Uint8List(_samples.length * 2);
    final bd = ByteData.sublistView(pcm);
    for (int i = 0; i < _samples.length; i++) {
      bd.setInt16(i * 2, _samples[i], Endian.little);
    }
    _samples.clear();
    return pcm;
  }

  /// Drain generated samples as a list of 16-bit signed integers.
  List<int> drainSamplesList() {
    final result = List<int>.from(_samples);
    _samples.clear();
    return result;
  }

  /// Number of pending samples.
  int get pendingSamples => _samples.length;

  static int _toSigned32(int v) {
    if (v >= 0x80000000) return v - 0x100000000;
    return v;
  }
}
