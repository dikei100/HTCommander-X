/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Audio sample buffer management for multi-device encoding/decoding.
/// Port of HTCommander.Core/hamlib/AudioBuffer.cs
///
/// Note: Dart's main isolate is single-threaded, so no locking is needed
/// (unlike the C# version which uses lock objects). If used across isolates,
/// wrap with appropriate synchronization.
library;

import 'dart:typed_data';

class AudioBuffer {
  final List<List<int>> _buffers;

  AudioBuffer(int numDevices)
      : _buffers = List.generate(numDevices, (_) => <int>[]);

  /// Add a sample to the buffer for a specific device.
  void put(int device, int sample) {
    _buffers[device].add(sample);
  }

  /// Get all samples from a device buffer and clear it.
  Int16List getAndClear(int device) {
    final samples = Int16List.fromList(_buffers[device]);
    _buffers[device].clear();
    return samples;
  }

  /// Get the current number of samples in a buffer.
  int getCount(int device) => _buffers[device].length;

  /// Clear a specific device buffer.
  void clear(int device) {
    _buffers[device].clear();
  }

  /// Clear all device buffers.
  void clearAll() {
    for (final buf in _buffers) {
      buf.clear();
    }
  }
}
