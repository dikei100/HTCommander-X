/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Extended AX.25 frame construction methods for U, S, and I frames.
/// Port of HTCommander.Core/hamlib/Ax25Pad2.cs
///
/// The original ax25_pad.dart was written with APRS in mind and handles UI
/// frames. This adds support for the more general cases of AX.25 frames
/// needed by the connected-mode data link state machine.
library;

import 'ax25_pad.dart';

/// Extended AX.25 frame construction.
class Ax25Pad2 {
  Ax25Pad2._();

  // -------------------------------------------------------------------------
  // U Frame Construction
  // -------------------------------------------------------------------------

  /// Construct a U (Unnumbered) frame.
  ///
  /// [addrs]    Array of addresses (destination, source, digipeaters).
  /// [numAddr]  Number of addresses, range 2..10.
  /// [cr]       Command/response flag.
  /// [ftype]    Frame type (SABME, SABM, DISC, DM, UA, FRMR, UI, XID, TEST).
  /// [pf]       Poll/Final flag.
  /// [pid]      Protocol ID (used ONLY for UI type, normally 0xF0).
  /// [pinfo]    Data for Info field (allowed for UI, XID, TEST, FRMR).
  /// [infoLen]  Length of Info field.
  static Packet? uFrame(
    List<String> addrs,
    int numAddr,
    CmdRes cr,
    Ax25FrameType ftype,
    int pf,
    int pid,
    List<int>? pinfo,
    int infoLen,
  ) {
    final thisP = Packet();
    thisP.modulo = Ax25Modulo.unknown;

    if (!_setAddrs(thisP, addrs, numAddr, cr)) return null;

    int ctrl = 0;
    int i = 0; // Is Info part allowed?

    switch (ftype) {
      case Ax25FrameType.uSABME:
        ctrl = 0x6F;
        break;
      case Ax25FrameType.uSABM:
        ctrl = 0x2F;
        break;
      case Ax25FrameType.uDISC:
        ctrl = 0x43;
        break;
      case Ax25FrameType.uDM:
        ctrl = 0x0F;
        break;
      case Ax25FrameType.uUA:
        ctrl = 0x63;
        break;
      case Ax25FrameType.uFRMR:
        ctrl = 0x87;
        i = 1;
        break;
      case Ax25FrameType.uUI:
        ctrl = 0x03;
        i = 1;
        break;
      case Ax25FrameType.uXID:
        ctrl = 0xAF;
        i = 1;
        break;
      case Ax25FrameType.uTEST:
        ctrl = 0xE3;
        i = 1;
        break;
      default:
        return null;
    }

    if (pf != 0) ctrl |= 0x10;

    // Add control byte
    thisP.frameData[thisP.frameLen++] = ctrl;

    // Add PID for UI frames
    if (ftype == Ax25FrameType.uUI) {
      if (pid <= 0 || pid == 0xFF) pid = Ax25Constants.pidNoLayer3;
      thisP.frameData[thisP.frameLen++] = pid;
    }

    // Add information field if allowed and provided
    if (i != 0) {
      if (pinfo != null && infoLen > 0) {
        final actualLen =
            infoLen > Ax25Constants.maxInfoLen ? Ax25Constants.maxInfoLen : infoLen;
        for (int j = 0; j < actualLen; j++) {
          thisP.frameData[thisP.frameLen + j] = pinfo[j];
        }
        thisP.frameLen += actualLen;
      }
    }

    thisP.frameData[thisP.frameLen] = 0;
    assert(thisP.frameLen <= Ax25Constants.maxPacketLen);

    return thisP;
  }

  // -------------------------------------------------------------------------
  // S Frame Construction
  // -------------------------------------------------------------------------

  /// Construct an S (Supervisory) frame.
  ///
  /// [addrs]    Array of addresses.
  /// [numAddr]  Number of addresses, range 2..10.
  /// [cr]       Command/response flag.
  /// [ftype]    Frame type (RR, RNR, REJ, SREJ).
  /// [modulo]   8 or 128 (determines 1 or 2 control bytes).
  /// [nr]       N(R) field — receive sequence number.
  /// [pf]       Poll/Final flag.
  /// [pinfo]    Data for Info field (allowed only for SREJ).
  /// [infoLen]  Length of Info field.
  static Packet? sFrame(
    List<String> addrs,
    int numAddr,
    CmdRes cr,
    Ax25FrameType ftype,
    int modulo,
    int nr,
    int pf,
    List<int>? pinfo,
    int infoLen,
  ) {
    final thisP = Packet();

    if (!_setAddrs(thisP, addrs, numAddr, cr)) return null;

    if (modulo != 8 && modulo != 128) modulo = 8;
    thisP.modulo = modulo == 128 ? Ax25Modulo.modulo128 : Ax25Modulo.modulo8;

    if (nr < 0 || nr >= modulo) nr &= (modulo - 1);

    int ctrl = 0;
    switch (ftype) {
      case Ax25FrameType.sRR:
        ctrl = 0x01;
        break;
      case Ax25FrameType.sRNR:
        ctrl = 0x05;
        break;
      case Ax25FrameType.sREJ:
        ctrl = 0x09;
        break;
      case Ax25FrameType.sSREJ:
        ctrl = 0x0D;
        break;
      default:
        return null;
    }

    if (modulo == 8) {
      if (pf != 0) ctrl |= 0x10;
      ctrl |= (nr << 5);
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    } else {
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
      ctrl = (pf & 1) | (nr << 1);
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    }

    // Add info field for SREJ if provided
    if (ftype == Ax25FrameType.sSREJ && pinfo != null && infoLen > 0) {
      final actualLen =
          infoLen > Ax25Constants.maxInfoLen ? Ax25Constants.maxInfoLen : infoLen;
      for (int j = 0; j < actualLen; j++) {
        thisP.frameData[thisP.frameLen + j] = pinfo[j];
      }
      thisP.frameLen += actualLen;
    }

    thisP.frameData[thisP.frameLen] = 0;
    assert(thisP.frameLen <= Ax25Constants.maxPacketLen);

    return thisP;
  }

  // -------------------------------------------------------------------------
  // I Frame Construction
  // -------------------------------------------------------------------------

  /// Construct an I (Information) frame.
  ///
  /// [addrs]    Array of addresses.
  /// [numAddr]  Number of addresses, range 2..10.
  /// [cr]       Command/response flag.
  /// [modulo]   8 or 128.
  /// [nr]       N(R) field — receive sequence number.
  /// [ns]       N(S) field — send sequence number.
  /// [pf]       Poll/Final flag.
  /// [pid]      Protocol ID (normally 0xF0).
  /// [pinfo]    Data for Info field.
  /// [infoLen]  Length of Info field.
  static Packet? iFrame(
    List<String> addrs,
    int numAddr,
    CmdRes cr,
    int modulo,
    int nr,
    int ns,
    int pf,
    int pid,
    List<int>? pinfo,
    int infoLen,
  ) {
    final thisP = Packet();

    if (!_setAddrs(thisP, addrs, numAddr, cr)) return null;

    if (modulo != 8 && modulo != 128) modulo = 8;
    thisP.modulo = modulo == 128 ? Ax25Modulo.modulo128 : Ax25Modulo.modulo8;

    if (nr < 0 || nr >= modulo) nr &= (modulo - 1);
    if (ns < 0 || ns >= modulo) ns &= (modulo - 1);

    int ctrl = 0;

    if (modulo == 8) {
      ctrl = (nr << 5) | (ns << 1);
      if (pf != 0) ctrl |= 0x10;
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    } else {
      ctrl = ns << 1;
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
      ctrl = (nr << 1);
      if (pf != 0) ctrl |= 0x01;
      thisP.frameData[thisP.frameLen++] = ctrl & 0xFF;
    }

    // Add PID
    if (pid <= 0 || pid == 0xFF) pid = Ax25Constants.pidNoLayer3;
    thisP.frameData[thisP.frameLen++] = pid;

    // Add information field
    if (pinfo != null && infoLen > 0) {
      final actualLen =
          infoLen > Ax25Constants.maxInfoLen ? Ax25Constants.maxInfoLen : infoLen;
      for (int j = 0; j < actualLen; j++) {
        thisP.frameData[thisP.frameLen + j] = pinfo[j];
      }
      thisP.frameLen += actualLen;
    }

    thisP.frameData[thisP.frameLen] = 0;
    assert(thisP.frameLen <= Ax25Constants.maxPacketLen);

    return thisP;
  }

  // -------------------------------------------------------------------------
  // Helper Methods
  // -------------------------------------------------------------------------

  /// Set address fields in the packet.
  static bool _setAddrs(
      Packet pp, List<String> addrs, int numAddr, CmdRes cr) {
    assert(pp.frameLen == 0);

    if (numAddr < Ax25Constants.minAddrs || numAddr > Ax25Constants.maxAddrs) {
      return false;
    }

    for (int n = 0; n < numAddr; n++) {
      final offset = n * 7;

      final parsed = Packet.parseAddr(n, addrs[n], true);
      if (parsed == null) return false;

      // Fill in address (6 bytes, shifted left 1 bit)
      for (int i = 0; i < 6; i++) {
        if (i < parsed.callsign.length) {
          pp.frameData[offset + i] =
              (parsed.callsign.codeUnitAt(i) << 1) & 0xFF;
        } else {
          pp.frameData[offset + i] = (' '.codeUnitAt(0) << 1) & 0xFF;
        }
      }

      // Fill in SSID byte
      int ssidByte = 0x60 | ((parsed.ssid & 0xF) << 1);

      // Set command/response flag
      switch (n) {
        case Ax25Constants.destination:
          if (cr == CmdRes.cmd) ssidByte |= 0x80;
          break;
        case Ax25Constants.source:
          if (cr == CmdRes.res) ssidByte |= 0x80;
          break;
        default:
          break;
      }

      // Set last address bit if this is the final address
      if (n == numAddr - 1) ssidByte |= 0x01;

      pp.frameData[offset + 6] = ssidByte & 0xFF;
      pp.frameLen += 7;
    }

    pp.numAddr = numAddr;
    return true;
  }
}
