/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// HDLC frame reception and decoding.
/// https://www.ietf.org/rfc/rfc1549.txt
///
/// Port of HTCommander.Core/hamlib/HdlcRec.cs
///
/// This is the original (v1) HDLC receiver. For the advanced multi-slicer
/// version with bit-error correction, see hdlc_rec2.dart.
library;

import 'dart:typed_data';

import 'audio_config.dart';
import 'fcs_calc.dart';

// ---------------------------------------------------------------------------
// Support types
// ---------------------------------------------------------------------------

/// Audio level information for received frames.
class AudioLevel {
  int rec;
  int mark;
  int space;

  AudioLevel({this.rec = 9999, this.mark = 9999, this.space = 9999});
}

/// Raw received bit buffer — stores raw bits from demodulator.
class RawReceivedBitBuffer {
  RawReceivedBitBuffer? next;
  final int chan;
  final int subchan;
  final int slice;
  AudioLevel audioLevel;
  double speedError;
  int length;
  final bool isScrambled;
  int descramState;
  int prevDescram;

  static const int _maxNumBits =
      ((AudioConfig.maxRadioChannels * 2048 + 2) * 8 * 6 ~/ 5);
  final Uint8List _data;

  RawReceivedBitBuffer(
    this.chan,
    this.subchan,
    this.slice,
    this.isScrambled,
    this.descramState,
    this.prevDescram,
  )   : _data = Uint8List(_maxNumBits),
        audioLevel = AudioLevel(),
        speedError = 0,
        length = 0;

  void clear(bool isScrambled, int descramState, int prevDescram) {
    next = null;
    audioLevel = AudioLevel();
    speedError = 0;
    length = 0;
    this.descramState = descramState;
    this.prevDescram = prevDescram;
  }

  void appendBit(int val) {
    if (length >= _maxNumBits) return; // Silently discard if full
    _data[length] = val;
    length++;
  }

  int getBit(int index) {
    if (index >= length) return 0;
    return _data[index];
  }

  void chop8() {
    if (length >= 8) length -= 8;
  }
}

/// HDLC receiver state for a single channel/subchannel/slice.
class _HdlcState {
  int prevRaw = 0; // Previous raw bit for NRZI
  int lfsr = 0; // Descrambler shift register for 9600 baud
  int prevDescram = 0; // Previous descrambled bit
  int patDet = 0; // 8-bit pattern detector shift register
  int flag4Det = 0; // Last 32 raw bits for flag detection
  int oAcc = 0; // Octet accumulator
  int oLen = -1; // Number of bits in accumulator (-1 = disabled)
  late Uint8List frameBuffer; // Frame being assembled
  int frameLen = 0; // Length of frame
  RawReceivedBitBuffer? rrbb; // Raw bit buffer

  // EAS (Emergency Alert System) fields
  int easAcc = 0; // EAS accumulator (64 bits)
  bool easGathering = false;
  bool easPlusFound = false;
  int easFieldsAfterPlus = 0;

  _HdlcState() {
    frameBuffer = Uint8List(AudioConfig.maxRadioChannels * 2048 + 2);
  }
}

// ---------------------------------------------------------------------------
// Event argument types
// ---------------------------------------------------------------------------

/// Event data for frame received.
class FrameReceivedEvent {
  final int channel;
  final int subchannel;
  final int slice;
  final Uint8List frame;
  final int frameLength;
  final AudioLevel audioLevel;

  FrameReceivedEvent({
    required this.channel,
    required this.subchannel,
    required this.slice,
    required this.frame,
    required this.frameLength,
    required this.audioLevel,
  });
}

/// Event data for DCD state change.
class DcdChangedEvent {
  final int channel;
  final bool state;

  DcdChangedEvent({required this.channel, required this.state});
}

/// Callback types.
typedef FrameReceivedCallback = void Function(FrameReceivedEvent event);
typedef DcdChangedCallback = void Function(DcdChangedEvent event);

// ---------------------------------------------------------------------------
// HdlcRec
// ---------------------------------------------------------------------------

/// HDLC frame receiver — extracts AX.25 frames from a raw bit stream.
class HdlcRec {
  static const int _minFrameLen = 15 + 2; // AX25_MIN_PACKET_LEN + 2 for FCS
  static const int _maxFrameLen = 2048 + 2; // AX25_MAX_PACKET_LEN + 2 for FCS

  late List<List<List<_HdlcState?>>> _hdlcState;
  final List<int> _numSubchan;
  late List<List<int>> _compositeDcd;
  late AudioConfig _audioConfig;
  bool _wasInit = false;

  // Random number generator for BER injection
  int _seed = 1;

  /// Event raised when a valid frame is received.
  FrameReceivedCallback? onFrameReceived;

  /// Event raised when DCD state changes.
  DcdChangedCallback? onDcdChanged;

  HdlcRec()
      : _numSubchan = List.filled(AudioConfig.maxRadioChannels, 0) {
    _hdlcState = List.generate(
      AudioConfig.maxRadioChannels,
      (_) => List.generate(
        AudioConfig.maxSubchannels,
        (_) => List<_HdlcState?>.filled(AudioConfig.maxSlicers, null),
      ),
    );
    _compositeDcd = List.generate(
      AudioConfig.maxRadioChannels,
      (_) => List.filled(AudioConfig.maxSubchannels + 1, 0),
    );
  }

  /// Initialize the HDLC receiver.
  void init(AudioConfig audioConfig) {
    _audioConfig = audioConfig;

    for (final row in _compositeDcd) {
      row.fillRange(0, row.length, 0);
    }

    for (int ch = 0; ch < AudioConfig.maxRadioChannels; ch++) {
      if (_audioConfig.channelMedium[ch] == Medium.radio) {
        _numSubchan[ch] = _audioConfig.channels[ch].numSubchan;
        assert(_numSubchan[ch] >= 1 &&
            _numSubchan[ch] <= AudioConfig.maxSubchannels);

        for (int sub = 0; sub < _numSubchan[ch]; sub++) {
          for (int slice = 0; slice < AudioConfig.maxSlicers; slice++) {
            final h = _HdlcState();
            _hdlcState[ch][sub][slice] = h;
            h.rrbb = RawReceivedBitBuffer(
              ch,
              sub,
              slice,
              _audioConfig.channels[ch].modemType == ModemType.scramble,
              h.lfsr,
              h.prevDescram,
            );
          }
        }
      }
    }

    _wasInit = true;
  }

  int _myRand() {
    _seed = ((_seed * 1103515245 + 12345) & 0x7fffffff);
    return _seed;
  }

  /// Process a single received bit (main entry point).
  void recBit(int chan, int subchan, int slice, int raw, bool isScrambled,
      int notUsedRemove) {
    int dummyLL = 0;
    int dummy = 0;
    recBitNew(
        chan, subchan, slice, raw, isScrambled, notUsedRemove, dummyLL, dummy);
  }

  /// Process a single received bit with PLL tracking.
  /// Returns (pllNudgeTotal, pllSymbolCount) for caller tracking.
  ({int pllNudgeTotal, int pllSymbolCount}) recBitNew(
    int chan,
    int subchan,
    int slice,
    int raw,
    bool isScrambled,
    int notUsedRemove,
    int pllNudgeTotal,
    int pllSymbolCount,
  ) {
    assert(_wasInit);
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    assert(subchan >= 0 && subchan < AudioConfig.maxSubchannels);
    assert(slice >= 0 && slice < AudioConfig.maxSlicers);

    // EAS does not use HDLC
    if (_audioConfig.channels[chan].modemType == ModemType.eas) {
      _easRecBit(chan, subchan, slice, raw, notUsedRemove);
      return (pllNudgeTotal: pllNudgeTotal, pllSymbolCount: pllSymbolCount);
    }

    final h = _hdlcState[chan][subchan][slice]!;

    // NRZI decoding: 0 bit = transition, 1 bit = no change
    int dbit;
    if (isScrambled) {
      final descram = _descramble(raw, h);
      dbit = (descram == h.prevDescram) ? 1 : 0;
      h.prevDescram = descram;
      h.prevRaw = raw;
    } else {
      dbit = (raw == h.prevRaw) ? 1 : 0;
      h.prevRaw = raw;
    }

    // Shift bit through pattern detector
    h.patDet = (h.patDet >> 1) & 0xFF;
    if (dbit != 0) h.patDet |= 0x80;

    h.flag4Det = (h.flag4Det >> 1) & 0xFFFFFFFF;
    if (dbit != 0) h.flag4Det |= 0x80000000;

    h.rrbb!.appendBit(raw);

    // Check for flag pattern 01111110 (0x7e)
    if (h.patDet == 0x7e) {
      h.rrbb!.chop8();

      // End of frame or start of frame
      if (h.rrbb!.length >= _minFrameLen * 8) {
        // End of frame
        double speedError = 0;
        if (pllSymbolCount > 0) {
          speedError = pllNudgeTotal *
                  100.0 /
                  (256.0 * 256.0 * 256.0 * 256.0) /
                  pllSymbolCount +
              0.02;
        }
        h.rrbb!.speedError = speedError;
        h.rrbb!.audioLevel = AudioLevel(rec: 0, mark: 0, space: 0);

        _processRawBits(h.rrbb!);
        h.rrbb = null;

        // Allocate new buffer
        h.rrbb = RawReceivedBitBuffer(
            chan, subchan, slice, isScrambled, h.lfsr, h.prevDescram);
      } else {
        // Start of frame
        pllNudgeTotal = 0;
        pllSymbolCount = -1;
        h.rrbb!.clear(isScrambled, h.lfsr, h.prevDescram);
      }

      h.oLen = 0;
      h.frameLen = 0;
      h.rrbb!.appendBit(h.prevRaw);
    }
    // Check for loss of signal pattern (7 or 8 ones in a row)
    else if (h.patDet == 0xfe) {
      h.oLen = -1;
      h.frameLen = 0;
      h.rrbb!.clear(isScrambled, h.lfsr, h.prevDescram);
    }
    // Check for bit stuffing pattern (5 ones followed by 0)
    else if ((h.patDet & 0xfc) == 0x7c) {
      // Discard the stuffed 0 bit
    } else {
      // Accumulate bits into octets
      if (h.oLen >= 0) {
        h.oAcc = (h.oAcc >> 1) & 0xFF;
        if (dbit != 0) h.oAcc |= 0x80;
        h.oLen++;

        if (h.oLen == 8) {
          h.oLen = 0;
          if (h.frameLen < _maxFrameLen) {
            h.frameBuffer[h.frameLen] = h.oAcc;
            h.frameLen++;
          }
        }
      }
    }

    return (pllNudgeTotal: pllNudgeTotal, pllSymbolCount: pllSymbolCount);
  }

  /// Descramble a bit for 9600 baud G3RUH/K9NG scrambling.
  /// Polynomial: x^17 + x^12 + 1
  int _descramble(int input, _HdlcState h) {
    final bit16 = (h.lfsr >> 16) & 1;
    final bit11 = (h.lfsr >> 11) & 1;
    final output = (input ^ bit16 ^ bit11) & 1;
    h.lfsr = ((h.lfsr << 1) | (input & 1)) & 0x1ffff;
    return output;
  }

  /// Process raw bits buffer — NRZI decode, destuff, verify FCS.
  void _processRawBits(RawReceivedBitBuffer rrbb) {
    final frame = Uint8List(_maxFrameLen);
    int frameLen = 0;
    int acc = 0;
    int bitCount = 0;
    int onesCount = 0;
    int prevRaw = rrbb.getBit(0);
    bool skipNext = false;

    for (int i = 1; i < rrbb.length; i++) {
      final raw = rrbb.getBit(i);

      // NRZI decode: no transition = 1, transition = 0
      final dbit = (raw == prevRaw) ? 1 : 0;
      prevRaw = raw;

      // Skip stuffed bit
      if (skipNext) {
        skipNext = false;
        onesCount = 0;
        continue;
      }

      // Check for bit stuffing (5 ones → next 0 is stuffed)
      if (dbit == 1) {
        onesCount++;
        if (onesCount == 5) {
          skipNext = true;
        }
      } else {
        onesCount = 0;
      }

      // Accumulate bits (LSB first)
      acc = (acc >> 1) & 0xFF;
      if (dbit != 0) acc |= 0x80;
      bitCount++;

      if (bitCount == 8) {
        if (frameLen < _maxFrameLen) frame[frameLen++] = acc;
        bitCount = 0;
        acc = 0;
      }
    }

    // Check if we have a valid frame
    if (frameLen >= _minFrameLen) {
      // Verify FCS
      final actualFcs = frame[frameLen - 2] | (frame[frameLen - 1] << 8);
      final expectedFcs = FcsCalc.calculate(frame, frameLen - 2);

      if (actualFcs == expectedFcs) {
        // Valid frame — pass to upper layers
        final frameData = Uint8List.fromList(frame.sublist(0, frameLen - 2));
        onFrameReceived?.call(FrameReceivedEvent(
          channel: rrbb.chan,
          subchannel: rrbb.subchan,
          slice: rrbb.slice,
          frame: frameData,
          frameLength: frameLen - 2,
          audioLevel: rrbb.audioLevel,
        ));
      }
    }
  }

  /// EAS (Emergency Alert System) bit receiver.
  void _easRecBit(int chan, int subchan, int slice, int raw, int futureUse) {
    final h = _hdlcState[chan][subchan][slice]!;

    // Accumulate most recent 64 bits
    h.easAcc = ((h.easAcc >> 1) & 0x7FFFFFFFFFFFFFFF);
    if (raw != 0) h.easAcc |= 0x8000000000000000; // ignore: avoid_js_rounded_ints

    const preambleZczc = 0x435a435aabababab; // ignore: avoid_js_rounded_ints
    const preambleNnnn = 0x4e4e4e4eabababab; // ignore: avoid_js_rounded_ints
    const easMaxLen = 268;

    bool done = false;

    if (h.easAcc == preambleZczc) {
      h.oLen = 0;
      h.easGathering = true;
      h.easPlusFound = false;
      h.easFieldsAfterPlus = 0;
      h.frameBuffer.fillRange(0, h.frameBuffer.length, 0);
      final zczc = [0x5A, 0x43, 0x5A, 0x43]; // "ZCZC"
      for (int i = 0; i < 4; i++) {
        h.frameBuffer[i] = zczc[i];
      }
      h.frameLen = 4;
    } else if (h.easAcc == preambleNnnn) {
      h.oLen = 0;
      h.easGathering = true;
      h.frameBuffer.fillRange(0, h.frameBuffer.length, 0);
      final nnnn = [0x4E, 0x4E, 0x4E, 0x4E]; // "NNNN"
      for (int i = 0; i < 4; i++) {
        h.frameBuffer[i] = nnnn[i];
      }
      h.frameLen = 4;
      done = true;
    } else if (h.easGathering) {
      h.oLen++;
      if (h.oLen == 8) {
        h.oLen = 0;
        final ch = (h.easAcc >> 56) & 0xFF;
        h.frameBuffer[h.frameLen++] = ch;

        // Validate character
        if (!((ch >= 0x20 && ch <= 0x7f) || ch == 0x0D || ch == 0x0A)) {
          h.easGathering = false;
          return;
        }
        if (h.frameLen > easMaxLen) {
          h.easGathering = false;
          return;
        }
        if (ch == 0x2B) {
          // '+'
          h.easPlusFound = true;
          h.easFieldsAfterPlus = 0;
        }
        if (h.easPlusFound && ch == 0x2D) {
          // '-'
          h.easFieldsAfterPlus++;
          if (h.easFieldsAfterPlus == 3) done = true;
        }
      }
    }

    if (done) {
      final frameData = Uint8List.fromList(
          h.frameBuffer.sublist(0, h.frameLen));
      onFrameReceived?.call(FrameReceivedEvent(
        channel: chan,
        subchannel: subchan,
        slice: slice,
        frame: frameData,
        frameLength: h.frameLen,
        audioLevel: AudioLevel(rec: 0, mark: 0, space: 0),
      ));
      h.easGathering = false;
    }
  }

  /// DCD (Data Carrier Detect) state change.
  void dcdChange(int chan, int subchan, int slice, bool state) {
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    assert(subchan >= 0 && subchan <= AudioConfig.maxSubchannels);
    assert(slice >= 0 && slice < AudioConfig.maxSlicers);

    final old = dataDetectAny(chan);

    if (state) {
      _compositeDcd[chan][subchan] |= (1 << slice);
    } else {
      _compositeDcd[chan][subchan] &= ~(1 << slice);
    }

    final newState = dataDetectAny(chan);
    if (newState != old) {
      onDcdChanged?.call(DcdChangedEvent(channel: chan, state: newState));
    }
  }

  /// Check if any decoder on this channel detects data.
  bool dataDetectAny(int chan) {
    assert(chan >= 0 && chan < AudioConfig.maxRadioChannels);
    for (int sc = 0; sc < _numSubchan[chan]; sc++) {
      if (_compositeDcd[chan][sc] != 0) return true;
    }
    return false;
  }
}
