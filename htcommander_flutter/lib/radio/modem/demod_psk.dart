/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// PSK (Phase Shift Keying) Demodulator for 2400 and 4800 bps.
/// Port of HTCommander.Core/hamlib/DemodPsk.cs
library;

import 'dart:math';
import 'dart:typed_data';

import 'dsp.dart';
import 'demod_9600.dart'; // shares DemodulatorState, SlicerState
import 'hdlc_rec2.dart';

/// V.26 alternative selection.
enum V26Alternative { unspecified, a, b }

/// PSK modem type.
enum PskModemType { qpsk, psk8 }

// ---------------------------------------------------------------------------
// PSK-specific state
// ---------------------------------------------------------------------------

/// PSK demodulator state.
class PskState {
  V26Alternative v26Alt = V26Alternative.unspecified;
  final Float64List sinTable256 = Float64List(256);

  // Pre-filter.
  int usePrefilter = 0;
  double prefilterBaud = 0;
  double preFilterWidthSym = 0;
  BpWindowType preWindow = BpWindowType.cosine;
  int preFilterTaps = 0;
  final Float64List audioIn = Float64List(Dsp.maxFilterSize);
  final Float64List preFilter = Float64List(Dsp.maxFilterSize);

  // Local oscillator.
  int pskUseLo = 0;
  int loStep = 0;
  int loPhase = 0;

  // After mixing.
  final Float64List iRaw = Float64List(Dsp.maxFilterSize);
  final Float64List qRaw = Float64List(Dsp.maxFilterSize);

  // Delay line.
  int bOffs = 0;
  int cOffs = 0;
  int sOffs = 0;
  double delayLineWidthSym = 0;
  int delayLineTaps = 0;
  final Float64List delayLine = Float64List(Dsp.maxFilterSize);

  // Low pass filter.
  double lpfBaud = 0;
  double lpFilterWidthSym = 0;
  int lpFilterTaps = 0;
  BpWindowType lpWindow = BpWindowType.cosine;
  final Float64List lpFilter = Float64List(Dsp.maxFilterSize);
}

// Phase-to-Gray code tables.
const List<int> _phaseToGrayV26 = [0, 1, 3, 2];
const List<int> _phaseToGrayV27 = [1, 0, 2, 3, 7, 6, 4, 5];

// DCD constants.
const int _dcdThreshOn = 30;
const int _dcdThreshOff = 6;
const int _dcdGoodWidth = 512;

// ---------------------------------------------------------------------------
// DemodPsk
// ---------------------------------------------------------------------------

/// PSK Demodulator for 2400 and 4800 bps Phase Shift Keying.
class DemodPsk {
  final HdlcRec2 _hdlcRec;

  DemodPsk(this._hdlcRec);

  /// Initialize PSK demodulator.
  ///
  /// [modemType]    - QPSK or 8PSK
  /// [v26Alt]       - V.26 alternative (for QPSK)
  /// [samplesPerSec]- Audio sample rate
  /// [bps]          - Bits per second
  /// [profile]      - Tuning profile character (P/Q/R/S for QPSK, T/U/V/W for 8PSK)
  /// [d]            - Demodulator state
  /// [psk]          - PSK-specific state
  void init(PskModemType modemType, V26Alternative v26Alt,
      int samplesPerSec, int bps, String profile,
      DemodulatorState d, PskState psk) {
    int correctBaud;
    int carrierFreq;
    psk.v26Alt = v26Alt;
    d.numSlicers = 1;

    if (modemType == PskModemType.qpsk) {
      correctBaud = bps ~/ 2;
      carrierFreq = 1800;

      switch (profile.toUpperCase()) {
        case 'P':
          psk.usePrefilter = 0;
          psk.lpfBaud = 0.60;
          psk.lpFilterWidthSym = 1.061;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.95;
          d.pllSearchingInertia = 0.50;
          break;
        case 'Q':
          psk.usePrefilter = 1;
          psk.prefilterBaud = 1.3;
          psk.preFilterWidthSym = 1.497;
          psk.preWindow = BpWindowType.cosine;
          psk.lpfBaud = 0.60;
          psk.lpFilterWidthSym = 1.061;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.87;
          d.pllSearchingInertia = 0.50;
          break;
        case 'S':
          psk.pskUseLo = 1;
          psk.usePrefilter = 1;
          psk.prefilterBaud = 0.55;
          psk.preFilterWidthSym = 2.014;
          psk.preWindow = BpWindowType.flattop;
          psk.lpfBaud = 0.60;
          psk.lpFilterWidthSym = 1.061;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;
        default: // 'R'
          psk.pskUseLo = 1;
          psk.usePrefilter = 0;
          psk.lpfBaud = 0.70;
          psk.lpFilterWidthSym = 1.007;
          psk.lpWindow = BpWindowType.truncated;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;
      }
      psk.delayLineWidthSym = 1.25;
      psk.cOffs =
          (11.0 / 12.0 * samplesPerSec / correctBaud).round();
      psk.bOffs = (samplesPerSec / correctBaud).round();
      psk.sOffs =
          (13.0 / 12.0 * samplesPerSec / correctBaud).round();
    } else {
      // 8PSK
      correctBaud = bps ~/ 3;
      carrierFreq = 1800;

      switch (profile.toUpperCase()) {
        case 'T':
          psk.usePrefilter = 0;
          psk.lpfBaud = 1.15;
          psk.lpFilterWidthSym = 0.871;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.95;
          d.pllSearchingInertia = 0.50;
          break;
        case 'U':
          psk.usePrefilter = 1;
          psk.prefilterBaud = 0.9;
          psk.preFilterWidthSym = 0.571;
          psk.preWindow = BpWindowType.flattop;
          psk.lpfBaud = 1.15;
          psk.lpFilterWidthSym = 0.871;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.87;
          d.pllSearchingInertia = 0.50;
          break;
        case 'W':
          psk.pskUseLo = 1;
          psk.usePrefilter = 1;
          psk.prefilterBaud = 0.85;
          psk.preFilterWidthSym = 0.844;
          psk.preWindow = BpWindowType.cosine;
          psk.lpfBaud = 0.85;
          psk.lpFilterWidthSym = 0.844;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;
        default: // 'V'
          psk.pskUseLo = 1;
          psk.usePrefilter = 0;
          psk.lpfBaud = 0.85;
          psk.lpFilterWidthSym = 0.844;
          psk.lpWindow = BpWindowType.cosine;
          d.pllLockedInertia = 0.925;
          d.pllSearchingInertia = 0.50;
          break;
      }
      psk.delayLineWidthSym = 1.25;
      psk.cOffs =
          (8.0 / 9.0 * samplesPerSec / correctBaud).round();
      psk.bOffs = (samplesPerSec / correctBaud).round();
      psk.sOffs =
          (10.0 / 9.0 * samplesPerSec / correctBaud).round();
    }

    // LO.
    if (psk.pskUseLo != 0) {
      psk.loStep =
          (pow(256.0, 4) * carrierFreq / samplesPerSec).round() &
              0xFFFFFFFF;
      for (int j = 0; j < 256; j++) {
        psk.sinTable256[j] = sin(2.0 * pi * j / 256.0);
      }
    }

    d.pllStepPerSample =
        (DemodulatorState.ticksPerPllCycle * correctBaud / samplesPerSec)
            .round();

    psk.preFilterTaps =
        (psk.preFilterWidthSym * samplesPerSec / correctBaud).round();
    psk.delayLineTaps =
        (psk.delayLineWidthSym * samplesPerSec / correctBaud).round();
    psk.lpFilterTaps =
        (psk.lpFilterWidthSym * samplesPerSec / correctBaud).round();

    if (psk.preFilterTaps > Dsp.maxFilterSize) {
      throw StateError('Pre filter size ${psk.preFilterTaps} too large');
    }
    if (psk.delayLineTaps > Dsp.maxFilterSize) {
      throw StateError('Delay line size ${psk.delayLineTaps} too large');
    }
    if (psk.lpFilterTaps > Dsp.maxFilterSize) {
      throw StateError('LP filter size ${psk.lpFilterTaps} too large');
    }

    if (psk.usePrefilter != 0) {
      double f1 = (carrierFreq - psk.prefilterBaud * correctBaud).toDouble();
      double f2 = (carrierFreq + psk.prefilterBaud * correctBaud).toDouble();
      if (f1 <= 0) f1 = 10;
      f1 /= samplesPerSec;
      f2 /= samplesPerSec;
      Dsp.genBandpass(f1, f2, psk.preFilter, psk.preFilterTaps, psk.preWindow);
    }

    final double fc = correctBaud * psk.lpfBaud / samplesPerSec;
    Dsp.genLowpass(fc, psk.lpFilter, psk.lpFilterTaps, psk.lpWindow);

    d.alevelMarkPeak = -1;
    d.alevelSpacePeak = -1;
  }

  /// Process one audio sample.
  void processSample(int chan, int subchan, int sam,
      PskModemType modemType, DemodulatorState d, PskState psk) {
    const int slice = 0;
    double fsam = sam / 16384.0;

    if (psk.usePrefilter != 0) {
      _pushSample(fsam, psk.audioIn, psk.preFilterTaps);
      fsam = _convolve(psk.audioIn, psk.preFilter, psk.preFilterTaps);
    }

    if (psk.pskUseLo != 0) {
      final double samXCos =
          fsam * psk.sinTable256[((psk.loPhase >> 24) + 64) & 0xFF];
      _pushSample(samXCos, psk.iRaw, psk.lpFilterTaps);
      final double ii = _convolve(psk.iRaw, psk.lpFilter, psk.lpFilterTaps);

      final double samXSin =
          fsam * psk.sinTable256[(psk.loPhase >> 24) & 0xFF];
      _pushSample(samXSin, psk.qRaw, psk.lpFilterTaps);
      final double qq = _convolve(psk.qRaw, psk.lpFilter, psk.lpFilterTaps);

      final double a = atan2(ii, qq);
      _pushSample(a, psk.delayLine, psk.delayLineTaps);
      final double delta = a - psk.delayLine[psk.bOffs];

      final List<int> bitQuality = [0, 0, 0];
      int gray;
      if (modemType == PskModemType.qpsk) {
        if (psk.v26Alt == V26Alternative.b) {
          gray = _phaseShiftToSymbol(delta + (-pi / 4), 2, bitQuality);
        } else {
          gray = _phaseShiftToSymbol(delta, 2, bitQuality);
        }
      } else {
        gray = _phaseShiftToSymbol(delta, 3, bitQuality);
      }
      _nudgePll(chan, subchan, slice, gray, modemType, d, psk, bitQuality);
      psk.loPhase = (psk.loPhase + psk.loStep) & 0xFFFFFFFF;
    } else {
      _pushSample(fsam, psk.delayLine, psk.delayLineTaps);

      final double samXCos = fsam * psk.delayLine[psk.cOffs];
      _pushSample(samXCos, psk.iRaw, psk.lpFilterTaps);
      final double ii = _convolve(psk.iRaw, psk.lpFilter, psk.lpFilterTaps);

      final double samXSin = fsam * psk.delayLine[psk.sOffs];
      _pushSample(samXSin, psk.qRaw, psk.lpFilterTaps);
      final double qq = _convolve(psk.qRaw, psk.lpFilter, psk.lpFilterTaps);

      final double delta = atan2(ii, qq);
      final List<int> bitQuality = [0, 0, 0];
      int gray;
      if (modemType == PskModemType.qpsk) {
        if (psk.v26Alt == V26Alternative.b) {
          gray = _phaseShiftToSymbol(delta + (pi / 2), 2, bitQuality);
        } else {
          gray = _phaseShiftToSymbol(delta + (3 * pi / 4), 2, bitQuality);
        }
      } else {
        gray = _phaseShiftToSymbol(delta + (3 * pi / 2), 3, bitQuality);
      }
      _nudgePll(chan, subchan, slice, gray, modemType, d, psk, bitQuality);
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static void _pushSample(double val, Float64List buff, int size) {
    for (int i = size - 1; i > 0; i--) {
      buff[i] = buff[i - 1];
    }
    buff[0] = val;
  }

  static double _convolve(Float64List data, Float64List filter, int size) {
    double sum = 0;
    for (int j = 0; j < size; j++) {
      sum += filter[j] * data[j];
    }
    return sum;
  }

  static int _phaseShiftToSymbol(
      double phaseShift, int bitsPerSymbol, List<int> bitQuality) {
    final int n = 1 << bitsPerSymbol;
    double a = phaseShift * n / (2 * pi);
    while (a >= n) a -= n;
    while (a < 0) a += n;
    int i = a.toInt();
    if (i >= n) i = n - 1;
    final double f = a - i;

    int result = 0;
    final List<int> table =
        bitsPerSymbol == 2 ? _phaseToGrayV26 : _phaseToGrayV27;
    for (int b = 0; b < bitsPerSymbol; b++) {
      final double demod = ((table[i] >> b) & 1) * (1.0 - f) +
          ((table[(i + 1) % n] >> b) & 1) * f;
      if (demod >= 0.5) result |= 1 << b;
      bitQuality[b] = (100.0 * 2.0 * (demod - 0.5).abs()).round();
    }
    return result;
  }

  void _nudgePll(int chan, int subchan, int slice, int demodBits,
      PskModemType modemType, DemodulatorState d, PskState psk,
      List<int> bitQuality) {
    final ss = d.slicer[slice];
    ss.prevDClockPll = ss.dataClockPll;
    ss.dataClockPll =
        (ss.dataClockPll + d.pllStepPerSample) & 0xFFFFFFFF;

    final int prev = _toSigned32(ss.prevDClockPll);
    final int curr = _toSigned32(ss.dataClockPll);
    if (curr < 0 && prev >= 0) {
      if (modemType == PskModemType.qpsk) {
        _hdlcRec.recBit(chan, subchan, slice, (demodBits >> 1) & 1);
        _hdlcRec.recBit(chan, subchan, slice, demodBits & 1);
      } else {
        _hdlcRec.recBit(chan, subchan, slice, (demodBits >> 2) & 1);
        _hdlcRec.recBit(chan, subchan, slice, (demodBits >> 1) & 1);
        _hdlcRec.recBit(chan, subchan, slice, demodBits & 1);
      }
      ss.pllSymbolCount++;
      _pllDcdEachSymbol(d, chan, subchan, slice);
    }

    if (demodBits != ss.prevDemodData) {
      _pllDcdSignalTransition(d, slice, _toSigned32(ss.dataClockPll));
      final int before = _toSigned32(ss.dataClockPll);
      if (ss.dataDetect != 0) {
        ss.dataClockPll =
            (before * d.pllLockedInertia).floor() & 0xFFFFFFFF;
      } else {
        ss.dataClockPll =
            (before * d.pllSearchingInertia).floor() & 0xFFFFFFFF;
      }
      ss.pllNudgeTotal += _toSigned32(ss.dataClockPll) - before;
    }
    ss.prevDemodData = demodBits;
  }

  void _pllDcdSignalTransition(DemodulatorState d, int slice, int dpllPhase) {
    if (dpllPhase > -_dcdGoodWidth * 1024 * 1024 &&
        dpllPhase < _dcdGoodWidth * 1024 * 1024) {
      d.slicer[slice].goodFlag = 1;
    } else {
      d.slicer[slice].badFlag = 1;
    }
  }

  void _pllDcdEachSymbol(
      DemodulatorState d, int chan, int subchan, int slice) {
    final ss = d.slicer[slice];
    ss.goodHist = ((ss.goodHist << 1) | ss.goodFlag) & 0xFF;
    ss.goodFlag = 0;
    ss.badHist = ((ss.badHist << 1) | ss.badFlag) & 0xFF;
    ss.badFlag = 0;
    ss.score = ((ss.score << 1) & 0xFFFFFFFF);
    ss.score |= ((_popCount(ss.goodHist) - _popCount(ss.badHist) >= 2) ? 1 : 0);

    final int scoreCount = _popCount32(ss.score);
    if (scoreCount >= _dcdThreshOn) {
      if (ss.dataDetect == 0) {
        ss.dataDetect = 1;
        _hdlcRec.recBit(chan, subchan, slice, 0); // DCD on notification
      }
    } else if (scoreCount <= _dcdThreshOff) {
      if (ss.dataDetect != 0) ss.dataDetect = 0;
    }
  }

  static int _popCount(int v) {
    v &= 0xFF;
    int c = 0;
    while (v != 0) {
      c++;
      v &= v - 1;
    }
    return c;
  }

  static int _popCount32(int v) {
    v &= 0xFFFFFFFF;
    int c = 0;
    while (v != 0) {
      c++;
      v &= v - 1;
    }
    return c;
  }

  static int _toSigned32(int v) {
    v &= 0xFFFFFFFF;
    if (v >= 0x80000000) return v - 0x100000000;
    return v;
  }
}
