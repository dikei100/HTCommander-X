/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Audio/modem configuration structures for the software modem pipeline.
/// Port of HTCommander.Core/hamlib/AudioConfig.cs
library;

/// Modem types.
enum ModemType {
  afsk,
  baseband,
  scramble,
  qpsk,
  psk8,
  off,
  qam16,
  qam64,
  ais,
  eas,
}

/// Layer 2 protocol types.
enum Layer2Type {
  ax25, // 0
  fx25, // 1
  il2p, // 2
}

/// V.26 alternatives.
enum V26Alternative {
  unspecified, // 0
  a, // 1
  b, // 2
}

/// Channel medium type.
enum Medium {
  none, // 0
  radio, // 1
  igate, // 2
  netTnc, // 3
}

/// Audio channel parameters.
class AudioChannelConfig {
  ModemType modemType;
  Layer2Type layer2Xmit;
  int markFreq;
  int spaceFreq;
  int baud;
  V26Alternative v26Alt;
  int fx25Strength;
  int il2pMaxFec;
  bool il2pInvertPolarity;
  int decimate;
  int upsample;
  int numFreq;
  int offset;
  int numSlicers;
  int numSubchan;

  // Transmit timing parameters
  int dwait;
  int slottime;
  int persist;
  int txdelay;
  int txtail;
  int fulldup;

  AudioChannelConfig({
    this.modemType = ModemType.afsk,
    this.layer2Xmit = Layer2Type.ax25,
    this.markFreq = 1200,
    this.spaceFreq = 2200,
    this.baud = 1200,
    this.v26Alt = V26Alternative.b,
    this.fx25Strength = 1,
    this.il2pMaxFec = 0,
    this.il2pInvertPolarity = false,
    this.decimate = 1,
    this.upsample = 1,
    this.numFreq = 1,
    this.offset = 0,
    this.numSlicers = 1,
    this.numSubchan = 1,
    this.dwait = 0,
    this.slottime = 10,
    this.persist = 63,
    this.txdelay = 30,
    this.txtail = 10,
    this.fulldup = 0,
  });
}

/// Audio device parameters.
class AudioDeviceConfig {
  bool defined;
  String deviceIn;
  String deviceOut;
  int numChannels;
  int samplesPerSec;
  int bitsPerSample;

  AudioDeviceConfig({
    this.defined = false,
    this.deviceIn = '',
    this.deviceOut = '',
    this.numChannels = 1,
    this.samplesPerSec = 44100,
    this.bitsPerSample = 16,
  });
}

/// Main audio configuration structure.
class AudioConfig {
  static const int maxAudioDevices = 3;
  static const int maxRadioChannels = 6;
  static const int maxTotalChannels = 16;
  static const int maxSubchannels = 9;
  static const int maxSlicers = 9;

  final List<AudioDeviceConfig> devices;
  final List<AudioChannelConfig> channels;
  final List<Medium> channelMedium;
  final List<String> myCall;

  AudioConfig()
      : devices = List.generate(maxAudioDevices, (_) => AudioDeviceConfig()),
        channels =
            List.generate(maxRadioChannels, (_) => AudioChannelConfig()),
        channelMedium = List.filled(maxTotalChannels, Medium.none),
        myCall = List.filled(maxTotalChannels, '');

  /// Get audio device index for a given channel.
  static int channelToDevice(int channel) => channel >> 1;

  /// Get first channel for a given device.
  static int deviceFirstChannel(int device) => device * 2;
}
