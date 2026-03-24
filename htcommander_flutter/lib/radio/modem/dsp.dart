/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// DSP utilities - filter design, window functions, RRC pulse shaping.
/// Port of HTCommander.Core/hamlib/Dsp.cs
library;

import 'dart:math';
import 'dart:typed_data';

/// Window types for filter shaping.
enum BpWindowType {
  truncated,
  cosine,
  hamming,
  blackman,
  flattop,
}

/// Digital Signal Processing functions for generating filters used by
/// demodulators.
class Dsp {
  Dsp._();

  static const int maxFilterSize = 480;

  /// Filter window shape function.
  ///
  /// [type] - Window type (Hamming, Blackman, etc.)
  /// [size] - Number of filter taps
  /// [j]    - Index in range 0 to size-1
  /// Returns multiplier for the window shape.
  static double window(BpWindowType type, int size, int j) {
    final double center = 0.5 * (size - 1);

    switch (type) {
      case BpWindowType.cosine:
        return cos((j - center) / size * pi);

      case BpWindowType.hamming:
        return 0.53836 - 0.46164 * cos((j * 2 * pi) / (size - 1));

      case BpWindowType.blackman:
        return 0.42659 -
            0.49656 * cos((j * 2 * pi) / (size - 1)) +
            0.076849 * cos((j * 4 * pi) / (size - 1));

      case BpWindowType.flattop:
        return 1.0 -
            1.93 * cos((j * 2 * pi) / (size - 1)) +
            1.29 * cos((j * 4 * pi) / (size - 1)) -
            0.388 * cos((j * 6 * pi) / (size - 1)) +
            0.028 * cos((j * 8 * pi) / (size - 1));

      case BpWindowType.truncated:
        return 1.0;
    }
  }

  /// Generate low pass filter kernel.
  ///
  /// [fc]         - Cutoff frequency as fraction of sampling frequency
  /// [lpFilter]   - Output filter array (length >= [filterSize])
  /// [filterSize] - Number of filter taps
  /// [wtype]      - Window type
  static void genLowpass(
      double fc, Float64List lpFilter, int filterSize, BpWindowType wtype) {
    if (filterSize < 3 || filterSize > maxFilterSize) {
      throw ArgumentError(
          'Filter size must be between 3 and $maxFilterSize');
    }
    if (lpFilter.length < filterSize) {
      throw ArgumentError(
          'Filter array must have at least $filterSize elements');
    }

    final double center = 0.5 * (filterSize - 1);

    for (int j = 0; j < filterSize; j++) {
      double sinc;
      if ((j - center).abs() < 1e-12) {
        sinc = 2 * fc;
      } else {
        sinc = sin(2 * pi * fc * (j - center)) / (pi * (j - center));
      }
      final double shape = window(wtype, filterSize, j);
      lpFilter[j] = sinc * shape;
    }

    // Normalize for unity gain at DC.
    double g = 0;
    for (int j = 0; j < filterSize; j++) {
      g += lpFilter[j];
    }
    if (g.abs() > 1e-30) {
      for (int j = 0; j < filterSize; j++) {
        lpFilter[j] /= g;
      }
    }
  }

  /// Generate band pass filter kernel for the prefilter.
  ///
  /// [f1], [f2]   - Lower/upper cutoff as fraction of sampling frequency
  /// [bpFilter]   - Output filter array (length >= [filterSize])
  /// [filterSize] - Number of filter taps
  /// [wtype]      - Window type
  static void genBandpass(double f1, double f2, Float64List bpFilter,
      int filterSize, BpWindowType wtype) {
    if (filterSize < 3 || filterSize > maxFilterSize) {
      throw ArgumentError(
          'Filter size must be between 3 and $maxFilterSize');
    }
    if (bpFilter.length < filterSize) {
      throw ArgumentError(
          'Filter array must have at least $filterSize elements');
    }

    final double center = 0.5 * (filterSize - 1);

    for (int j = 0; j < filterSize; j++) {
      double sinc;
      if ((j - center).abs() < 1e-12) {
        sinc = 2 * (f2 - f1);
      } else {
        sinc = sin(2 * pi * f2 * (j - center)) / (pi * (j - center)) -
            sin(2 * pi * f1 * (j - center)) / (pi * (j - center));
      }
      final double shape = window(wtype, filterSize, j);
      bpFilter[j] = sinc * shape;
    }

    // Normalize for unity gain in middle of passband.
    final double w = 2 * pi * (f1 + f2) / 2;
    double g = 0;
    for (int j = 0; j < filterSize; j++) {
      g += 2 * bpFilter[j] * cos((j - center) * w);
    }
    if (g.abs() > 1e-30) {
      for (int j = 0; j < filterSize; j++) {
        bpFilter[j] /= g;
      }
    }
  }

  /// Generate mark/space tone filters.
  ///
  /// [fc]         - Tone frequency (Hz)
  /// [sps]        - Samples per second
  /// [sinTable]   - Output sine table (length >= [filterSize])
  /// [cosTable]   - Output cosine table (length >= [filterSize])
  /// [filterSize] - Number of filter taps
  /// [wtype]      - Window type
  static void genMs(int fc, int sps, Float64List sinTable,
      Float64List cosTable, int filterSize, BpWindowType wtype) {
    if (filterSize < 3 || filterSize > maxFilterSize) {
      throw ArgumentError(
          'Filter size must be between 3 and $maxFilterSize');
    }
    if (sinTable.length < filterSize || cosTable.length < filterSize) {
      throw ArgumentError(
          'Filter arrays must have at least $filterSize elements');
    }

    double gs = 0, gc = 0;

    for (int j = 0; j < filterSize; j++) {
      final double center = 0.5 * (filterSize - 1);
      final double am = ((j - center) / sps) * fc * (2.0 * pi);
      final double shape = window(wtype, filterSize, j);

      sinTable[j] = sin(am) * shape;
      cosTable[j] = cos(am) * shape;

      gs += sinTable[j] * sin(am);
      gc += cosTable[j] * cos(am);
    }

    // Normalize for unity gain.
    if (gs.abs() > 1e-30 && gc.abs() > 1e-30) {
      for (int j = 0; j < filterSize; j++) {
        sinTable[j] /= gs;
        cosTable[j] /= gc;
      }
    }
  }

  /// Root Raised Cosine function.
  ///
  /// [t] - Time in units of symbol duration
  /// [a] - Roll off factor, between 0 and 1
  static double rrc(double t, double a) {
    // sinc part
    double sinc;
    if (t > -0.001 && t < 0.001) {
      sinc = 1;
    } else {
      sinc = sin(pi * t) / (pi * t);
    }

    // window part
    double w;
    if ((a * t).abs() > 0.499 && (a * t).abs() < 0.501) {
      w = pi / 4;
    } else {
      w = cos(pi * a * t) / (1 - pow(2 * a * t, 2));
      // Allow negative values (matches C# behaviour).
    }

    return sinc * w;
  }

  /// Generate Root Raised Cosine low pass filter.
  ///
  /// [pfilter]          - Output filter array (length >= [filterTaps])
  /// [filterTaps]       - Number of filter taps
  /// [rolloff]          - Rolloff factor (0..1)
  /// [samplesPerSymbol] - Samples per symbol
  static void genRrcLowpass(Float64List pfilter, int filterTaps,
      double rolloff, double samplesPerSymbol) {
    if (filterTaps < 3 || filterTaps > maxFilterSize) {
      throw ArgumentError(
          'Filter taps must be between 3 and $maxFilterSize');
    }
    if (pfilter.length < filterTaps) {
      throw ArgumentError(
          'Filter array must have at least $filterTaps elements');
    }

    for (int k = 0; k < filterTaps; k++) {
      final double t =
          (k - ((filterTaps - 1.0) / 2.0)) / samplesPerSymbol;
      pfilter[k] = rrc(t, rolloff);
    }

    // Scale for unity gain.
    double sum = 0;
    for (int k = 0; k < filterTaps; k++) {
      sum += pfilter[k];
    }
    if (sum.abs() > 1e-30) {
      for (int k = 0; k < filterTaps; k++) {
        pfilter[k] /= sum;
      }
    }
  }
}
