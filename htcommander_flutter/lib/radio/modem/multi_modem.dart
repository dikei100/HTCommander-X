/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Multiple parallel decoders: coordinates multiple demodulators and slicers,
/// picks the best candidate frame from competing decoders.
/// Port of HTCommander.Core/hamlib/MultiModem.cs
library;

import 'dart:typed_data';

import 'hdlc_rec2.dart';

/// Candidate packet for best selection.
class CandidatePacket {
  Uint8List? frame;
  int frameLength = 0;
  AudioLevel audioLevel = const AudioLevel();
  FecType fecType = FecType.none;
  RetryType retries = RetryType.none;
  int age = 0;
  int crc = 0;
  int score = 0;
  CorrectionInfo? correctionInfo;
}

/// Event payload when a packet is selected for processing.
class PacketReadyEvent {
  final int channel;
  final int subchannel;
  final int slice;
  final Uint8List frame;
  final int frameLength;
  final AudioLevel audioLevel;
  final FecType fecType;
  final RetryType retries;
  final String spectrum;
  final int ctagNum;
  final CorrectionInfo? correctionInfo;

  const PacketReadyEvent({
    required this.channel,
    required this.subchannel,
    required this.slice,
    required this.frame,
    required this.frameLength,
    this.audioLevel = const AudioLevel(),
    this.fecType = FecType.none,
    this.retries = RetryType.none,
    this.spectrum = '',
    this.ctagNum = -1,
    this.correctionInfo,
  });
}

/// Multi-modem manager -- coordinates multiple demodulators and slicers.
class MultiModem {
  static const int maxChannels = 6;
  static const int maxSubchannels = 9;
  static const int maxSlicers = 9;
  static const int _processAfterBits = 3;

  // 3D candidate grid: [chan][subchan][slice].
  final List<List<List<CandidatePacket>>> _candidates;

  final List<int> _processAge;
  final List<bool> _fx25Busy;

  /// Callback invoked when the best candidate is selected.
  void Function(PacketReadyEvent event)? onPacketReady;

  /// Number of subchannels per channel (set during init).
  final List<int> numSubchannels;

  /// Number of slicers per channel (set during init).
  final List<int> numSlicers;

  MultiModem()
      : _candidates = List.generate(
            maxChannels,
            (_) => List.generate(
                maxSubchannels,
                (_) => List.generate(
                    maxSlicers, (_) => CandidatePacket()))),
        _processAge = List.filled(maxChannels, 0),
        _fx25Busy = List.filled(maxChannels, false),
        numSubchannels = List.filled(maxChannels, 1),
        numSlicers = List.filled(maxChannels, 1);

  /// Configure channel parameters.
  void initChannel(int chan,
      {int subchannels = 1,
      int slicers = 1,
      int sampleRate = 32000,
      int baud = 1200}) {
    numSubchannels[chan] = subchannels.clamp(1, maxSubchannels);
    numSlicers[chan] = slicers.clamp(1, maxSlicers);

    int realBaud = baud;
    _processAge[chan] = _processAfterBits * sampleRate ~/ realBaud;

    // Clear candidates.
    for (int s = 0; s < maxSubchannels; s++) {
      for (int sl = 0; sl < maxSlicers; sl++) {
        _candidates[chan][s][sl] = CandidatePacket();
      }
    }
  }

  /// Submit a received frame for candidate selection.
  void processRecFrame(int chan, int subchan, int slice, Uint8List frame,
      int frameLen, AudioLevel alevel, RetryType retries,
      {FecType fecType = FecType.none,
      int ctagNum = -1,
      CorrectionInfo? correctionInfo}) {
    // If single decoder with no FX.25 in progress, push through immediately.
    if (numSubchannels[chan] == 1 &&
        numSlicers[chan] == 1 &&
        !_fx25Busy[chan]) {
      onPacketReady?.call(PacketReadyEvent(
        channel: chan,
        subchannel: subchan,
        slice: slice,
        frame: Uint8List.fromList(frame.sublist(0, frameLen)),
        frameLength: frameLen,
        audioLevel: alevel,
        fecType: fecType,
        retries: retries,
        ctagNum: ctagNum,
        correctionInfo: correctionInfo,
      ));
      return;
    }

    // Otherwise save for later selection.
    final c = _candidates[chan][subchan][slice];
    c.frame = Uint8List.fromList(frame.sublist(0, frameLen));
    c.frameLength = frameLen;
    c.audioLevel = alevel;
    c.fecType = fecType;
    c.retries = retries;
    c.age = 0;
    c.correctionInfo = correctionInfo;
    // Simple CRC for duplicate detection.
    int crc = 0xFFFF;
    for (int i = 0; i < frameLen; i++) {
      crc = ((crc >> 8) ^ (crc ^ frame[i])) & 0xFFFF;
    }
    c.crc = crc;
  }

  /// Called periodically to age candidates and trigger selection.
  void tick(int chan) {
    for (int subchan = 0; subchan < numSubchannels[chan]; subchan++) {
      for (int slice = 0; slice < numSlicers[chan]; slice++) {
        final c = _candidates[chan][subchan][slice];
        if (c.frame != null) {
          c.age++;
          if (c.age > _processAge[chan]) {
            if (_fx25Busy[chan]) {
              c.age = 0;
            } else {
              _pickBestCandidate(chan);
              return;
            }
          }
        }
      }
    }
  }

  void _pickBestCandidate(int chan) {
    final int numBars = numSlicers[chan] * numSubchannels[chan];
    int bestScore = 0;
    int bestSubchan = 0;
    int bestSlice = 0;

    for (int n = 0; n < numBars; n++) {
      final int j = n % numSubchannels[chan];
      final int k = n ~/ numSubchannels[chan];
      final c = _candidates[chan][j][k];

      if (c.frame == null) {
        c.score = 0;
        continue;
      }

      if (c.fecType != FecType.none) {
        c.score = 9000 - 100 * c.retries.index;
      } else {
        c.score = RetryType.max.index * 1000 - c.retries.index * 1000 + 1;
      }

      // Boost if nearby have same CRC.
      for (int m = 0; m < numBars; m++) {
        if (m == n) continue;
        final int mj = m % numSubchannels[chan];
        final int mk = m ~/ numSubchannels[chan];
        final mc = _candidates[chan][mj][mk];
        if (mc.frame != null && mc.crc == c.crc) {
          c.score += (numBars + 1) - (m - n).abs();
        }
      }

      if (c.score > bestScore) {
        bestScore = c.score;
        bestSubchan = j;
        bestSlice = k;
      }
    }

    if (bestScore > 0) {
      final best = _candidates[chan][bestSubchan][bestSlice];
      onPacketReady?.call(PacketReadyEvent(
        channel: chan,
        subchannel: bestSubchan,
        slice: bestSlice,
        frame: best.frame!,
        frameLength: best.frameLength,
        audioLevel: best.audioLevel,
        fecType: best.fecType,
        retries: best.retries,
        correctionInfo: best.correctionInfo,
      ));
    }

    // Clear all candidates.
    for (int s = 0; s < maxSubchannels; s++) {
      for (int sl = 0; sl < maxSlicers; sl++) {
        _candidates[chan][s][sl] = CandidatePacket();
      }
    }
  }

  void setFx25Busy(int chan, bool busy) {
    if (chan >= 0 && chan < maxChannels) _fx25Busy[chan] = busy;
  }
}
