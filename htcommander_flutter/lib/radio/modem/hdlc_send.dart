/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// HDLC frame encoder with bit stuffing and NRZI encoding.
/// Port of HTCommander.Core/hamlib/HdlcSend.cs
library;

import 'dart:typed_data';

import 'fcs_calc.dart';
import 'gen_tone.dart';

/// HDLC frame encoder for transmitting data.
class HdlcSend {
  final GenTone _genTone;
  int _stuff = 0;
  int _output = 0;
  int _numberBitsSent = 0;

  HdlcSend(this._genTone);

  /// Send a complete AX.25 HDLC frame. Returns the number of bits sent.
  int sendFrame(Uint8List frameBuffer, int frameLen, {bool badFcs = false}) {
    _numberBitsSent = 0;

    // Start flag.
    _sendControlNrzi(0x7E);

    // Data bytes.
    for (int j = 0; j < frameLen; j++) {
      _sendDataNrzi(frameBuffer[j]);
    }

    // FCS.
    final int fcs = FcsCalc.calculate(frameBuffer, frameLen);
    if (badFcs) {
      _sendDataNrzi((~fcs) & 0xFF);
      _sendDataNrzi(((~fcs) >> 8) & 0xFF);
    } else {
      _sendDataNrzi(fcs & 0xFF);
      _sendDataNrzi((fcs >> 8) & 0xFF);
    }

    // End flag.
    _sendControlNrzi(0x7E);

    return _numberBitsSent;
  }

  /// Send preamble or postamble flags. Returns the number of bits sent.
  int sendFlags(int numFlags) {
    _numberBitsSent = 0;
    for (int j = 0; j < numFlags; j++) {
      _sendControlNrzi(0x7E);
    }
    return _numberBitsSent;
  }

  /// Send a control byte (flags) -- no bit stuffing.
  void _sendControlNrzi(int x) {
    for (int i = 0; i < 8; i++) {
      _sendBitNrzi(x & 1);
      x >>= 1;
    }
    _stuff = 0;
  }

  /// Send a data byte with bit stuffing and NRZI encoding.
  void _sendDataNrzi(int x) {
    for (int i = 0; i < 8; i++) {
      _sendBitNrzi(x & 1);
      if ((x & 1) != 0) {
        _stuff++;
        if (_stuff == 5) {
          _sendBitNrzi(0);
          _stuff = 0;
        }
      } else {
        _stuff = 0;
      }
      x >>= 1;
    }
  }

  /// Send a single bit with NRZI encoding.
  /// NRZI: data 1 -> no change, data 0 -> invert signal.
  void _sendBitNrzi(int b) {
    if (b == 0) {
      _output = _output == 0 ? 1 : 0;
    }
    _genTone.putBit(_output);
    _numberBitsSent++;
  }
}
