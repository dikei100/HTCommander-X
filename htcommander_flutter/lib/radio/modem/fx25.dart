/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// FX.25 Forward Error Correction protocol: correlation tags, RS encode/decode,
/// bit-stream receiver, and sender.
/// Combined port of Fx25.cs, Fx25Encode.cs, Fx25Rec.cs, Fx25Send.cs.
library;

import 'dart:typed_data';

import 'fcs_calc.dart';
import 'reed_solomon.dart';

// ---------------------------------------------------------------------------
// Correlation tag definitions
// ---------------------------------------------------------------------------

class _CorrelationTag {
  final int valueHi; // Upper 32 bits of 64-bit tag
  final int valueLo; // Lower 32 bits
  final int nBlockRadio;
  final int kDataRadio;
  final int nBlockRs;
  final int kDataRs;
  final int iTab;

  const _CorrelationTag(this.valueHi, this.valueLo, this.nBlockRadio,
      this.kDataRadio, this.nBlockRs, this.kDataRs, this.iTab);

  /// Combine hi/lo into a single 64-bit int (Dart ints are 64-bit).
  int get value => (valueHi << 32) | (valueLo & 0xFFFFFFFF);
}

class _CodecConfig {
  final int symSize;
  final int genPoly;
  final int fcs;
  final int prim;
  final int nRoots;
  ReedSolomonCodec? rs;

  _CodecConfig(this.symSize, this.genPoly, this.fcs, this.prim, this.nRoots);
}

// ---------------------------------------------------------------------------
// Fx25 static configuration
// ---------------------------------------------------------------------------

/// FX.25 protocol constants and helpers.
class Fx25 {
  Fx25._();

  static const int ctagMin = 0x01;
  static const int ctagMax = 0x0B;
  static const int maxData = 239;
  static const int maxCheck = 64;
  static const int blockSize = 255;
  static const int _closeEnough = 8;

  static final List<_CodecConfig> _codecTab = [
    _CodecConfig(8, 0x11D, 1, 1, 16), // RS(255,239)
    _CodecConfig(8, 0x11D, 1, 1, 32), // RS(255,223)
    _CodecConfig(8, 0x11D, 1, 1, 64), // RS(255,191)
  ];

  // Tag table -- 64-bit values split into hi/lo 32-bit halves.
  static const List<_CorrelationTag> _tags = [
    _CorrelationTag(0x566ED271, 0x7946107E, 0, 0, 0, 0, -1), // 00 reserved
    _CorrelationTag(0xB74DB7DF, 0x8A532F3E, 255, 239, 255, 239, 0), // 01
    _CorrelationTag(0x26FF60A6, 0x00CC8FDE, 144, 128, 255, 239, 0), // 02
    _CorrelationTag(0xC7DC0508, 0xF3D9B09E, 80, 64, 255, 239, 0), // 03
    _CorrelationTag(0x8F056EB4, 0x369660EE, 48, 32, 255, 239, 0), // 04
    _CorrelationTag(0x6E260B1A, 0xC5835FAE, 255, 223, 255, 223, 1), // 05
    _CorrelationTag(0xFF94DC63, 0x4F1CFF4E, 160, 128, 255, 223, 1), // 06
    _CorrelationTag(0x1EB7B9CD, 0xBC09C00E, 96, 64, 255, 223, 1), // 07
    _CorrelationTag(0xDBF869BD, 0x2DBB1776, 64, 32, 255, 223, 1), // 08
    _CorrelationTag(0x3ADB0C13, 0xDEAE2836, 255, 191, 255, 191, 2), // 09
    _CorrelationTag(0xAB69DB6A, 0x543188D6, 192, 128, 255, 191, 2), // 0A
    _CorrelationTag(0x4A4ABEC4, 0xA724B796, 128, 64, 255, 191, 2), // 0B
    _CorrelationTag(0x0293D578, 0x626B67E6, 0, 0, 0, 0, -1), // 0C
    _CorrelationTag(0xE3B0B0D6, 0x917E58A6, 0, 0, 0, 0, -1), // 0D
    _CorrelationTag(0x720267AF, 0x1BE1F846, 0, 0, 0, 0, -1), // 0E
    _CorrelationTag(0x93210201, 0xE8F4C706, 0, 0, 0, 0, -1), // 0F
  ];

  static bool _initialized = false;

  /// Initialize FX.25 subsystem (creates RS codecs).
  static void init() {
    if (_initialized) return;
    for (int i = 0; i < _codecTab.length; i++) {
      _codecTab[i].rs = ReedSolomonCodec.create(
        symsize: _codecTab[i].symSize,
        gfpoly: _codecTab[i].genPoly,
        fcr: _codecTab[i].fcs,
        prim: _codecTab[i].prim,
        nroots: _codecTab[i].nRoots,
      );
      if (_codecTab[i].rs == null) {
        throw StateError('FX.25 internal error: RS init failed for tab $i');
      }
    }
    _initialized = true;
  }

  static ReedSolomonCodec getRs(int ctagNum) {
    assert(ctagNum >= ctagMin && ctagNum <= ctagMax);
    init();
    return _codecTab[_tags[ctagNum].iTab].rs!;
  }

  static int getCtagValue64(int ctagNum) => _tags[ctagNum].value;
  static int getKDataRadio(int ctagNum) => _tags[ctagNum].kDataRadio;
  static int getKDataRs(int ctagNum) => _tags[ctagNum].kDataRs;
  static int getNRoots(int ctagNum) =>
      _codecTab[_tags[ctagNum].iTab].nRoots;

  /// Pick suitable transmission format.
  static int pickMode(int fxMode, int dlen) {
    if (fxMode <= 0) return -1;

    if (fxMode - 100 >= ctagMin && fxMode - 100 <= ctagMax) {
      return dlen <= getKDataRadio(fxMode - 100) ? fxMode - 100 : -1;
    }

    if (fxMode == 16 || fxMode == 32 || fxMode == 64) {
      for (int k = ctagMax; k >= ctagMin; k--) {
        if (fxMode == getNRoots(k) && dlen <= getKDataRadio(k)) return k;
      }
      return -1;
    }

    const prefer = [0x04, 0x03, 0x06, 0x09, 0x05, 0x01];
    for (final m in prefer) {
      if (dlen <= getKDataRadio(m)) return m;
    }
    return -1;
  }

  /// Find matching correlation tag.
  static int tagFindMatch(int t) {
    for (int c = ctagMin; c <= ctagMax; c++) {
      if (_popCount64(t ^ _tags[c].value) <= _closeEnough) return c;
    }
    return -1;
  }

  static int _popCount64(int x) {
    int count = 0;
    while (x != 0) {
      count++;
      x &= x - 1;
    }
    return count;
  }
}

// ---------------------------------------------------------------------------
// FX.25 Receiver
// ---------------------------------------------------------------------------

enum _Fx25State { fxTag, fxData, fxCheck }

class _Fx25Context {
  _Fx25State state = _Fx25State.fxTag;
  int accum = 0;
  int ctagNum = -1;
  int kDataRadio = 0;
  int coffs = 0;
  int nRoots = 0;
  int dlen = 0;
  int clen = 0;
  int iMask = 0x01;
  final Uint8List block = Uint8List(Fx25.blockSize + 1);

  _Fx25Context() {
    block[Fx25.blockSize] = 0x55; // fence
  }
}

/// Callback for FX.25 decoded frames.
typedef Fx25FrameCallback = void Function(
    int chan, int subchan, int slice, Uint8List frame, int frameLen,
    int corrections);

/// FX.25 bit-stream receiver.
class Fx25Rec {
  static const int _maxChans = 6;
  static const int _maxSubchans = 9;
  static const int _maxSlicers = 9;

  // Flat map indexed by (chan * _maxSubchans * _maxSlicers + subchan * _maxSlicers + slice).
  final Map<int, _Fx25Context> _contexts = {};

  Fx25FrameCallback? onFrameDecoded;

  /// Process a single received data bit.
  void recBit(int chan, int subchan, int slice, int dbit) {
    Fx25.init();
    final int key =
        chan * _maxSubchans * _maxSlicers + subchan * _maxSlicers + slice;
    final f = _contexts.putIfAbsent(key, () => _Fx25Context());

    switch (f.state) {
      case _Fx25State.fxTag:
        f.accum = (f.accum >> 1) & 0x7FFFFFFFFFFFFFFF; // unsigned shift
        if (dbit != 0) f.accum |= 1 << 63;

        final int c = Fx25.tagFindMatch(f.accum);
        if (c >= Fx25.ctagMin && c <= Fx25.ctagMax) {
          f.ctagNum = c;
          f.kDataRadio = Fx25.getKDataRadio(c);
          f.nRoots = Fx25.getNRoots(c);
          f.coffs = Fx25.getKDataRs(c);
          f.iMask = 0x01;
          f.dlen = 0;
          f.clen = 0;
          for (int i = 0; i < Fx25.blockSize; i++) {
            f.block[i] = 0;
          }
          f.block[Fx25.blockSize] = 0x55;
          f.state = _Fx25State.fxData;
        }
        break;

      case _Fx25State.fxData:
        if (dbit != 0) f.block[f.dlen] |= f.iMask;
        f.iMask = (f.iMask << 1) & 0xFF;
        if (f.iMask == 0) {
          f.iMask = 0x01;
          f.dlen++;
          if (f.dlen >= f.kDataRadio) f.state = _Fx25State.fxCheck;
        }
        break;

      case _Fx25State.fxCheck:
        if (dbit != 0) f.block[f.coffs + f.clen] |= f.iMask;
        f.iMask = (f.iMask << 1) & 0xFF;
        if (f.iMask == 0) {
          f.iMask = 0x01;
          f.clen++;
          if (f.clen >= f.nRoots) {
            _processRsBlock(chan, subchan, slice, f);
            f.ctagNum = -1;
            f.accum = 0;
            f.state = _Fx25State.fxTag;
          }
        }
        break;
    }
  }

  /// Check if FX.25 reception is in progress on a channel.
  bool isBusy(int chan) {
    for (int i = 0; i < _maxSubchans; i++) {
      for (int j = 0; j < _maxSlicers; j++) {
        final int key =
            chan * _maxSubchans * _maxSlicers + i * _maxSlicers + j;
        final f = _contexts[key];
        if (f != null && f.state != _Fx25State.fxTag) return true;
      }
    }
    return false;
  }

  void _processRsBlock(
      int chan, int subchan, int slice, _Fx25Context f) {
    assert(f.block[Fx25.blockSize] == 0x55);

    final rs = Fx25.getRs(f.ctagNum);
    final int derrors = ReedSolomon.decode(rs, f.block);

    if (derrors >= 0) {
      final frameBuf = Uint8List(Fx25.maxData + 1);
      final int frameLen = _unstuff(f.block, f.dlen, frameBuf);

      if (frameLen >= 14 + 1 + 2) {
        final int actualFcs =
            frameBuf[frameLen - 2] | (frameBuf[frameLen - 1] << 8);
        final int expectedFcs = FcsCalc.calculate(frameBuf, frameLen - 2);

        if (actualFcs == expectedFcs) {
          onFrameDecoded?.call(
            chan,
            subchan,
            slice,
            Uint8List.fromList(frameBuf.sublist(0, frameLen - 2)),
            frameLen - 2,
            derrors,
          );
        }
      }
    }
  }

  /// Remove HDLC bit stuffing and surrounding flags.
  static int _unstuff(Uint8List pin, int ilen, Uint8List frameBuf) {
    int patDet = 0;
    int oacc = 0;
    int olen = 0;
    int frameLen = 0;
    int idx = 0;

    if (pin[0] != 0x7E) return 0;

    while (ilen > 0 && pin[idx] == 0x7E) {
      ilen--;
      idx++;
    }

    for (int i = 0; i < ilen; idx++, i++) {
      for (int imask = 0x01; imask < 0x100; imask <<= 1) {
        final int dbit = (pin[idx] & imask) != 0 ? 1 : 0;
        patDet = ((patDet >> 1) | (dbit << 7)) & 0xFF;

        if (patDet == 0xFE) return 0; // 7 ones -- abort.

        if (dbit != 0) {
          oacc = ((oacc >> 1) | 0x80) & 0xFF;
        } else {
          if (patDet == 0x7E) {
            return (olen == 7) ? frameLen : 0;
          } else if ((patDet >> 2) == 0x1F) {
            continue; // Stuff bit -- discard.
          }
          oacc = (oacc >> 1) & 0xFF;
        }

        olen++;
        if ((olen & 8) != 0) {
          olen = 0;
          frameBuf[frameLen++] = oacc;
        }
      }
    }
    return 0;
  }
}

// ---------------------------------------------------------------------------
// FX.25 Sender
// ---------------------------------------------------------------------------

/// FX.25 frame encoder / sender.
class Fx25Send {
  /// Encode a frame into FX.25 format.
  ///
  /// [fbuf]   - AX.25 frame (without FCS)
  /// [flen]   - Length of frame
  /// [fxMode] - FX.25 mode selector
  ///
  /// Returns the encoded block as raw bytes (correlation tag + data + check),
  /// or null on failure.
  static Uint8List? encodeFrame(Uint8List fbuf, int flen, int fxMode) {
    Fx25.init();

    // Append FCS.
    final withFcs = Uint8List(flen + 2);
    withFcs.setRange(0, flen, fbuf);
    final int fcs = FcsCalc.calculate(fbuf, flen);
    withFcs[flen] = fcs & 0xFF;
    withFcs[flen + 1] = (fcs >> 8) & 0xFF;
    flen += 2;

    final data = Uint8List(Fx25.maxData + 1);
    data[Fx25.maxData] = 0xAA; // fence
    final int dlen = _stuffIt(withFcs, flen, data, Fx25.maxData);
    assert(data[Fx25.maxData] == 0xAA);
    if (dlen < 0) return null;

    final int ctagNum = Fx25.pickMode(fxMode, dlen);
    if (ctagNum < Fx25.ctagMin || ctagNum > Fx25.ctagMax) return null;

    final int kDataRadio = Fx25.getKDataRadio(ctagNum);
    final int shortenBy = Fx25.maxData - kDataRadio;
    if (shortenBy > 0) {
      for (int i = kDataRadio; i < kDataRadio + shortenBy; i++) {
        data[i] = 0;
      }
    }

    final check = Uint8List(Fx25.maxCheck + 1);
    check[Fx25.maxCheck] = 0xAA;
    final rs = Fx25.getRs(ctagNum);
    ReedSolomon.encode(rs, data, check);
    assert(check[Fx25.maxCheck] == 0xAA);

    final int nRoots = Fx25.getNRoots(ctagNum);

    // Build output: 8 bytes tag + kDataRadio data + nRoots check.
    final output = Uint8List(8 + kDataRadio + nRoots);
    final int ctagValue = Fx25.getCtagValue64(ctagNum);
    for (int k = 0; k < 8; k++) {
      output[k] = (ctagValue >> (k * 8)) & 0xFF;
    }
    output.setRange(8, 8 + kDataRadio, data);
    output.setRange(8 + kDataRadio, 8 + kDataRadio + nRoots, check);

    return output;
  }

  /// Bit-stuff AX.25 frame data into FX.25 data block format.
  static int _stuffIt(
      Uint8List inData, int ilen, Uint8List outData, int osize) {
    for (int i = 0; i < osize; i++) {
      outData[i] = 0;
    }
    outData[0] = 0x7E;
    int olen = 8;
    final int osizeBits = osize * 8;
    int ones = 0;

    for (int i = 0; i < ilen; i++) {
      for (int imask = 1; imask < 0x100; imask <<= 1) {
        final int v = (inData[i] & imask) != 0 ? 1 : 0;
        if (olen >= osizeBits) return -1;
        if (v != 0) {
          outData[olen >> 3] |= 1 << (olen & 0x7);
        }
        olen++;
        if (v != 0) {
          ones++;
          if (ones == 5) {
            if (olen >= osizeBits) return -1;
            olen++;
            ones = 0;
          }
        } else {
          ones = 0;
        }
      }
    }

    // Closing flag.
    const int flag = 0x7E;
    for (int imask = 1; imask < 0x100; imask <<= 1) {
      if (olen >= osizeBits) return -1;
      if ((flag & imask) != 0) {
        outData[olen >> 3] |= 1 << (olen & 0x7);
      }
      olen++;
    }

    final int ret = (olen + 7) ~/ 8;

    // Fill remainder with flag pattern.
    int imask2 = 1;
    while (olen < osizeBits) {
      if ((flag & imask2) != 0) {
        outData[olen >> 3] |= 1 << (olen & 0x7);
      }
      olen++;
      imask2 = ((imask2 << 1) | (imask2 >> 7)) & 0xFF;
    }

    return ret;
  }
}
