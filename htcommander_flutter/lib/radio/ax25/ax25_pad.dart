/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// AX.25 packet assembler and disassembler (raw frame level).
/// Port of HTCommander.Core/hamlib/Ax25Pad.cs
///
/// This operates at the raw byte/frame level for the software modem pipeline.
/// For the higher-level decoded packet representation, see ax25_packet.dart.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../modem/fcs_calc.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

class Ax25Constants {
  Ax25Constants._();

  static const int maxRepeaters = 8;
  static const int minAddrs = 2; // Destination & Source
  static const int maxAddrs = 10; // Destination, Source, 8 digipeaters

  static const int destination = 0;
  static const int source = 1;
  static const int repeater1 = 2;

  static const int maxAddrLen = 12;
  static const int minInfoLen = 0;
  static const int maxInfoLen = 2048;

  static const int minPacketLen = 2 * 7 + 1;
  static const int maxPacketLen = maxAddrs * 7 + 2 + 3 + maxInfoLen;

  static const int uiFrame = 0x03;
  static const int pidNoLayer3 = 0xF0;
  static const int pidNetrom = 0xCF;
  static const int pidSegmentationFragment = 0x08;
  static const int pidEscapeCharacter = 0xFF;

  // SSID bit masks
  static const int ssidHMask = 0x80;
  static const int ssidHShift = 7;
  static const int ssidRrMask = 0x60;
  static const int ssidRrShift = 5;
  static const int ssidSsidMask = 0x1E;
  static const int ssidSsidShift = 1;
  static const int ssidLastMask = 0x01;
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum Ax25FrameType {
  i, // Information
  sRR, // Receive Ready
  sRNR, // Receive Not Ready
  sREJ, // Reject Frame
  sSREJ, // Selective Reject
  uSABME, // Set Async Balanced Mode, Extended
  uSABM, // Set Async Balanced Mode
  uDISC, // Disconnect
  uDM, // Disconnect Mode
  uUA, // Unnumbered Acknowledge
  uFRMR, // Frame Reject
  uUI, // Unnumbered Information
  uXID, // Exchange Identification
  uTEST, // Test
  u, // Other Unnumbered
  notAX25, // Could not get control byte
}

enum CmdRes {
  cr00, // = 2
  cmd, // = 1
  res, // = 0
  cr11, // = 3
}

enum Ax25Modulo {
  unknown, // = 0
  modulo8, // = 8
  modulo128, // = 128
}

/// Audio level information.
class ALevel {
  int rec;
  int mark;
  int space;
  ALevel({this.rec = -1, this.mark = -1, this.space = -1});
}

// ---------------------------------------------------------------------------
// Parsed address result
// ---------------------------------------------------------------------------

class ParsedAddr {
  final String callsign;
  final int ssid;
  final bool heard;
  ParsedAddr(this.callsign, this.ssid, this.heard);
}

// ---------------------------------------------------------------------------
// Frame type result
// ---------------------------------------------------------------------------

class FrameTypeResult {
  final Ax25FrameType type;
  final CmdRes cr;
  final String desc;
  final int pf;
  final int nr;
  final int ns;
  FrameTypeResult(this.type, this.cr, this.desc, this.pf, this.nr, this.ns);
}

// ---------------------------------------------------------------------------
// Packet class
// ---------------------------------------------------------------------------

/// Represents a raw AX.25 packet at the frame level.
class Packet {
  static int _lastSeqNum = 0;
  static int _newCount = 0;

  final int seq;
  double releaseTime = 0;
  Packet? nextP;
  int numAddr;
  int frameLen;
  Ax25Modulo modulo;
  final Uint8List frameData;

  Packet()
      : seq = ++_lastSeqNum,
        frameData = Uint8List(Ax25Constants.maxPacketLen + 1),
        numAddr = -1,
        frameLen = 0,
        modulo = Ax25Modulo.unknown {
    _newCount++;
  }

  /// Create a new packet from text monitor format.
  static Packet? fromText(String monitor, bool strict) {
    if (monitor.isEmpty) return null;

    final packet = Packet();

    // Initialize with two addresses and control/pid for APRS
    for (int i = 0; i < 6; i++) {
      packet.frameData[Ax25Constants.destination * 7 + i] =
          (' '.codeUnitAt(0) << 1) & 0xFF;
      packet.frameData[Ax25Constants.source * 7 + i] =
          (' '.codeUnitAt(0) << 1) & 0xFF;
    }
    packet.frameData[Ax25Constants.destination * 7 + 6] =
        Ax25Constants.ssidHMask | Ax25Constants.ssidRrMask;
    packet.frameData[Ax25Constants.source * 7 + 6] =
        Ax25Constants.ssidRrMask | Ax25Constants.ssidLastMask;

    packet.frameData[14] = Ax25Constants.uiFrame;
    packet.frameData[15] = Ax25Constants.pidNoLayer3;

    packet.frameLen = 7 + 7 + 1 + 1;
    packet.numAddr = -1;
    packet.getNumAddr();

    // Separate addresses from rest
    final colonPos = monitor.indexOf(':');
    if (colonPos < 0) return null;

    final addrPart = monitor.substring(0, colonPos);
    final infoPart = monitor.substring(colonPos + 1);

    // Parse source address
    final gtPos = addrPart.indexOf('>');
    if (gtPos < 0) return null;

    final srcAddr = addrPart.substring(0, gtPos);
    final srcParsed = parseAddr(Ax25Constants.source, srcAddr, strict);
    if (srcParsed == null) return null;

    packet.setAddr(Ax25Constants.source, srcParsed.callsign);
    packet.setH(Ax25Constants.source);
    packet.setSsid(Ax25Constants.source, srcParsed.ssid);

    // Parse destination and digipeaters
    final parts = addrPart.substring(gtPos + 1).split(',');
    if (parts.isEmpty) return null;

    final destParsed = parseAddr(Ax25Constants.destination, parts[0], strict);
    if (destParsed == null) return null;

    packet.setAddr(Ax25Constants.destination, destParsed.callsign);
    packet.setH(Ax25Constants.destination);
    packet.setSsid(Ax25Constants.destination, destParsed.ssid);

    // Digipeaters
    for (int i = 1; i < parts.length && packet.numAddr < Ax25Constants.maxAddrs;
        i++) {
      final k = packet.numAddr;
      var digiAddr = parts[i];

      // Hack for q construct from APRS-IS
      if (!strict &&
          digiAddr.length >= 2 &&
          digiAddr[0] == 'q' &&
          digiAddr[1] == 'A') {
        digiAddr =
            'Q${digiAddr.substring(1, 2)}${digiAddr[2].toUpperCase()}${digiAddr.substring(3)}';
      }

      final digiParsed = parseAddr(k, digiAddr, strict);
      if (digiParsed == null) return null;

      packet.setAddr(k, digiParsed.callsign);
      packet.setSsid(k, digiParsed.ssid);

      if (digiParsed.heard) {
        for (int j = k; j >= Ax25Constants.repeater1; j--) {
          packet.setH(j);
        }
      }
    }

    // Process information part — translate <0xNN> to bytes
    final infoBytes = Uint8List(Ax25Constants.maxInfoLen);
    int infoLen = 0;
    int idx = 0;

    while (idx < infoPart.length && infoLen < Ax25Constants.maxInfoLen) {
      if (idx + 5 < infoPart.length &&
          infoPart[idx] == '<' &&
          infoPart[idx + 1] == '0' &&
          infoPart[idx + 2] == 'x' &&
          infoPart[idx + 5] == '>') {
        final hexStr = infoPart.substring(idx + 3, idx + 5);
        final b = int.tryParse(hexStr, radix: 16);
        if (b != null) {
          infoBytes[infoLen++] = b;
          idx += 6;
          continue;
        }
      }
      infoBytes[infoLen++] = infoPart.codeUnitAt(idx);
      idx++;
    }

    // Append info part
    for (int i = 0; i < infoLen; i++) {
      packet.frameData[packet.frameLen + i] = infoBytes[i];
    }
    packet.frameLen += infoLen;

    return packet;
  }

  /// Create a packet from frame data.
  static Packet? fromFrame(Uint8List fbuf, int flen, ALevel alevel) {
    if (flen < Ax25Constants.minPacketLen ||
        flen > Ax25Constants.maxPacketLen) {
      return null;
    }

    final packet = Packet();
    for (int i = 0; i < flen; i++) {
      packet.frameData[i] = fbuf[i];
    }
    packet.frameData[flen] = 0;
    packet.frameLen = flen;

    packet.numAddr = -1;
    packet.getNumAddr();

    return packet;
  }

  /// Duplicate a packet.
  Packet dup() {
    final newPacket = Packet();
    for (int i = 0; i < frameData.length; i++) {
      newPacket.frameData[i] = frameData[i];
    }
    newPacket.frameLen = frameLen;
    newPacket.numAddr = numAddr;
    newPacket.modulo = modulo;
    newPacket.releaseTime = releaseTime;
    return newPacket;
  }

  /// Parse an address string with optional SSID.
  static ParsedAddr? parseAddr(int position, String inAddr, bool strict) {
    if (inAddr.isEmpty) return null;

    final maxLen = strict ? 6 : (Ax25Constants.maxAddrLen - 1);
    final addr = StringBuffer();
    int ssid = 0;
    bool heard = false;

    int i = 0;
    while (i < inAddr.length && inAddr[i] != '-' && inAddr[i] != '*') {
      if (addr.length >= maxLen) return null;

      final ch = inAddr[i];
      if (!_isLetterOrDigit(ch)) return null;

      if (strict && ch.toLowerCase() == ch && ch.toUpperCase() != ch) {
        if (!inAddr.startsWith('qA')) return null;
      }

      addr.write(ch);
      i++;
    }

    final callsign = addr.toString();

    // Parse SSID
    if (i < inAddr.length && inAddr[i] == '-') {
      i++;
      final ssidStr = StringBuffer();

      while (i < inAddr.length && _isLetterOrDigit(inAddr[i])) {
        if (ssidStr.length >= 2) return null;
        if (strict && !_isDigit(inAddr[i])) return null;
        ssidStr.write(inAddr[i]);
        i++;
      }

      final parsed = int.tryParse(ssidStr.toString());
      if (parsed == null || parsed < 0 || parsed > 15) return null;
      ssid = parsed;
    }

    // Check for asterisk
    if (i < inAddr.length && inAddr[i] == '*') {
      heard = true;
      i++;
      if (strict == true) return null;
    }

    // Should be at end
    if (i < inAddr.length) return null;

    return ParsedAddr(callsign, ssid, heard);
  }

  /// Get number of addresses in packet.
  int getNumAddr() {
    if (numAddr >= 0) return numAddr;

    numAddr = 0;
    int addrBytes = 0;

    for (int a = 0; a < frameLen && addrBytes == 0; a++) {
      if ((frameData[a] & Ax25Constants.ssidLastMask) != 0) {
        addrBytes = a + 1;
      }
    }

    if (addrBytes % 7 == 0) {
      final addrs = addrBytes ~/ 7;
      if (addrs >= Ax25Constants.minAddrs && addrs <= Ax25Constants.maxAddrs) {
        numAddr = addrs;
      }
    }

    return numAddr;
  }

  /// Get number of repeater addresses.
  int getNumRepeaters() => numAddr >= 2 ? numAddr - 2 : 0;

  /// Get address with SSID.
  String getAddrWithSsid(int n) {
    if (n < 0 || n >= numAddr) return '??????';

    final station = StringBuffer();
    for (int i = 0; i < 6; i++) {
      station.writeCharCode((frameData[n * 7 + i] >> 1) & 0x7F);
    }

    var result = station.toString().trimRight();
    if (result.isEmpty) return '??????';

    final ssid = getSsid(n);
    if (ssid != 0) result = '$result-$ssid';

    return result;
  }

  /// Get address without SSID.
  String getAddrNoSsid(int n) {
    if (n < 0 || n >= numAddr) return '??????';

    final station = StringBuffer();
    for (int i = 0; i < 6; i++) {
      station.writeCharCode((frameData[n * 7 + i] >> 1) & 0x7F);
    }

    return station.toString().trimRight();
  }

  /// Get SSID of address.
  int getSsid(int n) {
    if (n >= 0 && n < numAddr) {
      return (frameData[n * 7 + 6] & Ax25Constants.ssidSsidMask) >>
          Ax25Constants.ssidSsidShift;
    }
    return 0;
  }

  /// Set SSID of address.
  void setSsid(int n, int ssid) {
    if (n >= 0 && n < numAddr) {
      frameData[n * 7 + 6] = ((frameData[n * 7 + 6] &
                  ~Ax25Constants.ssidSsidMask) |
              ((ssid << Ax25Constants.ssidSsidShift) &
                  Ax25Constants.ssidSsidMask)) &
          0xFF;
    }
  }

  /// Get "has been repeated" flag.
  bool getH(int n) {
    if (n >= 0 && n < numAddr) {
      return ((frameData[n * 7 + 6] & Ax25Constants.ssidHMask) >>
              Ax25Constants.ssidHShift) !=
          0;
    }
    return false;
  }

  /// Set "has been repeated" flag.
  void setH(int n) {
    if (n >= 0 && n < numAddr) {
      frameData[n * 7 + 6] |= Ax25Constants.ssidHMask;
    }
  }

  /// Get index of station we heard.
  int getHeard() {
    int result = Ax25Constants.source;
    for (int i = Ax25Constants.repeater1; i < getNumAddr(); i++) {
      if (getH(i)) result = i;
    }
    return result;
  }

  /// Get first repeater that has not been repeated.
  int getFirstNotRepeated() {
    for (int i = Ax25Constants.repeater1; i < getNumAddr(); i++) {
      if (!getH(i)) return i;
    }
    return -1;
  }

  /// Get RR bits.
  int getRr(int n) {
    if (n >= 0 && n < numAddr) {
      return (frameData[n * 7 + 6] & Ax25Constants.ssidRrMask) >>
          Ax25Constants.ssidRrShift;
    }
    return 0;
  }

  /// Set address.
  void setAddr(int n, String ad) {
    if (ad.isEmpty) return;

    if (n >= 0 && n < numAddr) {
      final parsed = parseAddr(n, ad, false);
      if (parsed == null) return;

      for (int i = 0; i < 6; i++) {
        frameData[n * 7 + i] = (' '.codeUnitAt(0) << 1) & 0xFF;
      }
      for (int i = 0; i < parsed.callsign.length && i < 6; i++) {
        frameData[n * 7 + i] =
            (parsed.callsign.codeUnitAt(i) << 1) & 0xFF;
      }
      setSsid(n, parsed.ssid);
    } else if (n == numAddr) {
      insertAddr(n, ad);
    }
  }

  /// Insert address at position.
  void insertAddr(int n, String ad) {
    if (ad.isEmpty) return;
    if (numAddr >= Ax25Constants.maxAddrs) return;
    if (n < Ax25Constants.repeater1 || n >= Ax25Constants.maxAddrs) return;

    // Clear last address flag
    frameData[numAddr * 7 - 1] &= (~Ax25Constants.ssidLastMask) & 0xFF;

    numAddr++;

    // Shift addresses
    for (int i = frameLen - 1; i >= n * 7; i--) {
      frameData[i + 7] = frameData[i];
    }
    for (int i = 0; i < 6; i++) {
      frameData[n * 7 + i] = (' '.codeUnitAt(0) << 1) & 0xFF;
    }
    frameData[n * 7 + 6] = Ax25Constants.ssidRrMask;
    frameLen += 7;

    // Set last address flag
    frameData[numAddr * 7 - 1] |= Ax25Constants.ssidLastMask;

    // Parse and set address
    final parsed = parseAddr(n, ad, false);
    if (parsed == null) return;

    for (int i = 0; i < parsed.callsign.length && i < 6; i++) {
      frameData[n * 7 + i] =
          (parsed.callsign.codeUnitAt(i) << 1) & 0xFF;
    }
    setSsid(n, parsed.ssid);
  }

  /// Remove address at position.
  void removeAddr(int n) {
    if (n < Ax25Constants.repeater1 || n >= Ax25Constants.maxAddrs) return;

    frameData[numAddr * 7 - 1] &= (~Ax25Constants.ssidLastMask) & 0xFF;
    numAddr--;

    for (int i = n * 7; i < frameLen - 7; i++) {
      frameData[i] = frameData[i + 7];
    }
    frameLen -= 7;

    frameData[numAddr * 7 - 1] |= Ax25Constants.ssidLastMask;
  }

  /// Get information field.
  Uint8List getInfo() {
    if (numAddr >= 2) {
      final offset = _getInfoOffset();
      final length = _getNumInfo();
      return Uint8List.fromList(
          frameData.sublist(offset, offset + length));
    }
    return Uint8List.fromList(frameData.sublist(0, frameLen));
  }

  /// Set information field.
  void setInfo(Uint8List newInfo, int newInfoLen) {
    final oldInfoLen = _getNumInfo();
    frameLen -= oldInfoLen;

    var len = newInfoLen.clamp(0, Ax25Constants.maxInfoLen);
    final offset = _getInfoOffset();
    for (int i = 0; i < len; i++) {
      frameData[offset + i] = newInfo[i];
    }
    frameLen += len;
  }

  /// Get control byte.
  int getControl() {
    if (frameLen == 0 || numAddr < 2) return -1;
    return frameData[_getControlOffset()];
  }

  /// Get second control byte (for modulo-128).
  int getC2() {
    if (frameLen == 0 || numAddr < 2) return -1;
    final offset2 = _getControlOffset() + 1;
    if (offset2 < frameLen) return frameData[offset2];
    return -1;
  }

  /// Get protocol ID.
  int getPid() {
    if (frameLen == 0 || numAddr < 2) return -1;
    return frameData[_getPidOffset()];
  }

  /// Set protocol ID.
  void setPid(int pid) {
    if (pid == 0) pid = Ax25Constants.pidNoLayer3;
    if (frameLen == 0) return;

    final ft = getFrameType();
    if (ft.type != Ax25FrameType.i && ft.type != Ax25FrameType.uUI) return;

    if (numAddr >= 2) {
      frameData[_getPidOffset()] = pid;
    }
  }

  /// Format all addresses for display.
  String formatAddrs() {
    if (numAddr == 0) return '';

    final result = StringBuffer();
    result.write(getAddrWithSsid(Ax25Constants.source));
    result.write('>');
    result.write(getAddrWithSsid(Ax25Constants.destination));

    final heard = getHeard();
    for (int i = Ax25Constants.repeater1; i < numAddr; i++) {
      result.write(',');
      result.write(getAddrWithSsid(i));
      if (i == heard) result.write('*');
    }

    result.write(':');
    return result.toString();
  }

  /// Get frame type with full decoding.
  FrameTypeResult getFrameType() {
    var cr = CmdRes.cr11;
    var pf = -1;
    var nr = -1;
    var ns = -1;

    int c = getControl();
    if (c < 0) {
      return FrameTypeResult(Ax25FrameType.notAX25, cr, 'Not AX.25', pf, nr, ns);
    }

    int c2 = 0;

    // Attempt to determine modulo
    if (modulo == Ax25Modulo.unknown && (c & 3) == 1 && getC2() != -1) {
      modulo = Ax25Modulo.modulo128;
    }

    if (modulo == Ax25Modulo.modulo128) {
      c2 = getC2();
    }

    final dstC = (frameData[Ax25Constants.destination * 7 + 6] &
                Ax25Constants.ssidHMask) !=
            0
        ? 1
        : 0;
    final srcC =
        (frameData[Ax25Constants.source * 7 + 6] & Ax25Constants.ssidHMask) !=
                0
            ? 1
            : 0;

    String crText, pfText;
    if (dstC != 0) {
      if (srcC != 0) {
        cr = CmdRes.cr11;
        crText = 'cc=11';
        pfText = 'p/f';
      } else {
        cr = CmdRes.cmd;
        crText = 'cmd';
        pfText = 'p';
      }
    } else {
      if (srcC != 0) {
        cr = CmdRes.res;
        crText = 'res';
        pfText = 'f';
      } else {
        cr = CmdRes.cr00;
        crText = 'cc=00';
        pfText = 'p/f';
      }
    }

    if ((c & 1) == 0) {
      // Information frame
      if (modulo == Ax25Modulo.modulo128) {
        ns = (c >> 1) & 0x7F;
        pf = c2 & 1;
        nr = (c2 >> 1) & 0x7F;
      } else {
        ns = (c >> 1) & 7;
        pf = (c >> 4) & 1;
        nr = (c >> 5) & 7;
      }
      return FrameTypeResult(
          Ax25FrameType.i, cr,
          'I $crText, n(s)=$ns, n(r)=$nr, $pfText=$pf, pid=0x${getPid().toRadixString(16).toUpperCase()}',
          pf, nr, ns);
    } else if ((c & 2) == 0) {
      // Supervisory frame
      if (modulo == Ax25Modulo.modulo128) {
        pf = c2 & 1;
        nr = (c2 >> 1) & 0x7F;
      } else {
        pf = (c >> 4) & 1;
        nr = (c >> 5) & 7;
      }

      switch ((c >> 2) & 3) {
        case 0:
          return FrameTypeResult(Ax25FrameType.sRR, cr,
              'RR $crText, n(r)=$nr, $pfText=$pf', pf, nr, ns);
        case 1:
          return FrameTypeResult(Ax25FrameType.sRNR, cr,
              'RNR $crText, n(r)=$nr, $pfText=$pf', pf, nr, ns);
        case 2:
          return FrameTypeResult(Ax25FrameType.sREJ, cr,
              'REJ $crText, n(r)=$nr, $pfText=$pf', pf, nr, ns);
        case 3:
          return FrameTypeResult(Ax25FrameType.sSREJ, cr,
              'SREJ $crText, n(r)=$nr, $pfText=$pf', pf, nr, ns);
      }
    } else {
      // Unnumbered frame
      pf = (c >> 4) & 1;

      switch (c & 0xEF) {
        case 0x6F:
          return FrameTypeResult(Ax25FrameType.uSABME, cr,
              'SABME $crText, $pfText=$pf', pf, nr, ns);
        case 0x2F:
          return FrameTypeResult(Ax25FrameType.uSABM, cr,
              'SABM $crText, $pfText=$pf', pf, nr, ns);
        case 0x43:
          return FrameTypeResult(Ax25FrameType.uDISC, cr,
              'DISC $crText, $pfText=$pf', pf, nr, ns);
        case 0x0F:
          return FrameTypeResult(Ax25FrameType.uDM, cr,
              'DM $crText, $pfText=$pf', pf, nr, ns);
        case 0x63:
          return FrameTypeResult(Ax25FrameType.uUA, cr,
              'UA $crText, $pfText=$pf', pf, nr, ns);
        case 0x87:
          return FrameTypeResult(Ax25FrameType.uFRMR, cr,
              'FRMR $crText, $pfText=$pf', pf, nr, ns);
        case 0x03:
          return FrameTypeResult(Ax25FrameType.uUI, cr,
              'UI $crText, $pfText=$pf', pf, nr, ns);
        case 0xAF:
          return FrameTypeResult(Ax25FrameType.uXID, cr,
              'XID $crText, $pfText=$pf', pf, nr, ns);
        case 0xE3:
          return FrameTypeResult(Ax25FrameType.uTEST, cr,
              'TEST $crText, $pfText=$pf', pf, nr, ns);
        default:
          return FrameTypeResult(
              Ax25FrameType.u, cr, 'U other???', pf, nr, ns);
      }
    }

    return FrameTypeResult(Ax25FrameType.notAX25, cr, '????', pf, nr, ns);
  }

  /// Check if packet is APRS format.
  bool isAprs() {
    if (frameLen == 0) return false;
    return numAddr >= 2 &&
        getControl() == Ax25Constants.uiFrame &&
        getPid() == Ax25Constants.pidNoLayer3;
  }

  /// Check if packet is null/empty.
  bool isNullFrame() => frameLen == 0;

  /// Calculate dedupe CRC (excludes digipeaters).
  int dedupeCrc() {
    final src = getAddrWithSsid(Ax25Constants.source);
    final dest = getAddrWithSsid(Ax25Constants.destination);
    final info = getInfo();
    var infoLen = info.length;

    // Remove trailing CR/LF/space
    while (infoLen >= 1 &&
        (info[infoLen - 1] == 0x0D ||
            info[infoLen - 1] == 0x0A ||
            info[infoLen - 1] == 0x20)) {
      infoLen--;
    }

    int crc = 0xFFFF;
    final srcBytes = Uint8List.fromList(ascii.encode(src));
    crc = FcsCalc.crc16(srcBytes, srcBytes.length, crc);
    final destBytes = Uint8List.fromList(ascii.encode(dest));
    crc = FcsCalc.crc16(destBytes, destBytes.length, crc);
    crc = FcsCalc.crc16(info, infoLen, crc);

    return crc;
  }

  /// Pack frame for transmission.
  int pack(Uint8List result) {
    for (int i = 0; i < frameLen; i++) {
      result[i] = frameData[i];
    }
    return frameLen;
  }

  // -----------------------------------------------------------------------
  // Private helpers
  // -----------------------------------------------------------------------

  int _getControlOffset() => numAddr * 7;

  int _getNumControl() {
    final c = frameData[_getControlOffset()];
    if ((c & 0x01) == 0) {
      return modulo == Ax25Modulo.modulo128 ? 2 : 1;
    }
    if ((c & 0x03) == 1) {
      return modulo == Ax25Modulo.modulo128 ? 2 : 1;
    }
    return 1; // U frame
  }

  int _getPidOffset() => _getControlOffset() + _getNumControl();

  int _getNumPid() {
    final c = frameData[_getControlOffset()];
    if ((c & 0x01) == 0 || c == 0x03 || c == 0x13) {
      final pidOffset = _getPidOffset();
      if (pidOffset < frameLen) {
        if (frameData[pidOffset] == Ax25Constants.pidEscapeCharacter) return 2;
        return 1;
      }
    }
    return 0;
  }

  int _getInfoOffset() =>
      _getControlOffset() + _getNumControl() + _getNumPid();

  int _getNumInfo() {
    final len = frameLen - numAddr * 7 - _getNumControl() - _getNumPid();
    return len < 0 ? 0 : len;
  }

  static bool _isLetterOrDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 48 && c <= 57) || // 0-9
        (c >= 65 && c <= 90) || // A-Z
        (c >= 97 && c <= 122); // a-z
  }

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 48 && c <= 57;
  }
}
