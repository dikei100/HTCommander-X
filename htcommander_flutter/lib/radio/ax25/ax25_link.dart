/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// AX.25 Data Link State Machine (DLSM).
/// Port of HTCommander.Core/hamlib/Ax25Link.cs
///
/// This is the low-level DLSM that implements the AX.25 v2.0/v2.2 protocol
/// state machine per the specification (X.25 LAPB derivative). For the
/// higher-level session abstraction, see ax25_session.dart.
///
/// The DLSM manages connected-mode AX.25 links including:
///   - Connection establishment (SABM/SABME → UA)
///   - Data transfer (I frames with flow control)
///   - Disconnection (DISC → UA)
///   - Timer management (T1 retransmit, T3 inactivity)
///   - Error recovery (REJ, SREJ, FRMR)
///   - Version negotiation (v2.0 ↔ v2.2 via XID)
library;

import 'dart:convert';
import 'dart:math';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

class Ax25LinkConstants {
  Ax25LinkConstants._();

  // Max bytes in Information part of frame
  static const int paclenMin = 1;
  static const int paclenDefault = 256;
  static const int paclenMax = 2048;

  // Number of times to retry before giving up
  static const int retryMin = 1;
  static const int retryDefault = 10;
  static const int retryMax = 15;

  // Number of seconds to wait before retrying
  static const int frackMin = 1;
  static const int frackDefault = 3;
  static const int frackMax = 15;

  // Window size — number of I frames before waiting for ack
  static const int maxframeBasicMin = 1;
  static const int maxframeBasicDefault = 4;
  static const int maxframeBasicMax = 7;

  static const int maxframeExtendedMin = 1;
  static const int maxframeExtendedDefault = 32;
  static const int maxframeExtendedMax = 63;

  static const double t3Default = 300.0; // 5 minutes of inactivity
  static const int generousK = 63; // For SREJ window calculations
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Data link state machine states.
enum DlsmState {
  disconnected, // 0
  awaitingConnection, // 1
  awaitingRelease, // 2
  connected, // 3
  timerRecovery, // 4
  awaitingV22Connection, // 5
}

/// SREJ enable options.
enum SrejEnable { none, single, multi, notSpecified }

/// MDL (Management Data Link) state.
enum MdlState { ready, negotiating }

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// Connected data block for transmit/receive queues.
class CData {
  int pid;
  List<int> data;
  int len;
  CData? next;

  CData(this.pid, this.data, this.len);

  CData.fromString(this.pid, String str, this.len)
      : data = ascii.encode(str).toList();
}

/// Registered callsign for incoming connections.
class RegCallsign {
  String callsign;
  int chan;
  int client;
  RegCallsign? next;

  RegCallsign(this.callsign, this.chan, this.client);
}

/// Configuration holder.
class MiscConfig {
  double frack;
  int paclen;
  int maxframeBasic;
  int maxframeExtended;
  int retry;
  int maxv22;
  List<String> v20Addrs;
  List<String> noxidAddrs;

  MiscConfig({
    this.frack = 3.0,
    this.paclen = 256,
    this.maxframeBasic = 4,
    this.maxframeExtended = 32,
    this.retry = 10,
    this.maxv22 = 3,
    List<String>? v20Addrs,
    List<String>? noxidAddrs,
  })  : v20Addrs = v20Addrs ?? [],
        noxidAddrs = noxidAddrs ?? [];
}

// ---------------------------------------------------------------------------
// DLSM instance
// ---------------------------------------------------------------------------

/// AX.25 Data Link State Machine instance.
class Ax25Dlsm {
  Ax25Dlsm? next;

  int streamId;
  int chan;
  int client;

  List<String> addrs = List.filled(10, '');
  int numAddr = 0;

  static const int ownCall = 0; // AX25_SOURCE
  static const int peerCall = 1; // AX25_DESTINATION

  double startTime;
  DlsmState state;

  int modulo;
  SrejEnable srejEnable;

  int n1Paclen;
  int n2Retry;
  int kMaxframe;

  int rc = 0;
  int vs = 0;
  int va = 0;
  int vr = 0;

  bool layerThreeInitiated = false;

  // Exception conditions
  bool peerReceiverBusy = false;
  bool rejectException = false;
  bool ownReceiverBusy = false;
  bool acknowledgePending = false;

  // Timing
  double srt;
  double t1v;

  bool radioChannelBusy = false;

  // Timer T1
  double t1Exp = 0;
  double t1PausedAt = 0;
  double t1RemainingWhenLastStopped = -999;
  bool t1HadExpired = false;

  // Timer T3
  double t3Exp = 0;

  // Statistics
  List<int> countRecvFrameType = List.filled(20, 0);
  int peakRcValue = 0;

  // Transmit/Receive queues
  CData? iFrameQueue;
  List<CData?> txdataByNs = List.filled(128, null);
  List<CData?> rxdataByNs = List.filled(128, null);

  // MDL state machine for XID exchange
  MdlState mdlState = MdlState.ready;
  int mdlRc = 0;
  double tm201Exp = 0;
  double tm201PausedAt = 0;

  // Segment reassembler
  CData? raBuff;
  int raFollowing = 0;

  Ax25Dlsm({
    this.streamId = 0,
    this.chan = 0,
    this.client = -1,
    this.state = DlsmState.disconnected,
    this.modulo = 8,
    this.srejEnable = SrejEnable.none,
    this.n1Paclen = Ax25LinkConstants.paclenDefault,
    this.n2Retry = Ax25LinkConstants.retryDefault,
    this.kMaxframe = Ax25LinkConstants.maxframeBasicDefault,
    this.srt = 1.5,
    this.t1v = 3.0,
    double? startTime,
  }) : startTime = startTime ?? _getTime();
}

// ---------------------------------------------------------------------------
// Time helper
// ---------------------------------------------------------------------------

double _getTime() =>
    DateTime.now().millisecondsSinceEpoch / 1000.0;

// ---------------------------------------------------------------------------
// Ax25Link — main class
// ---------------------------------------------------------------------------

/// AX.25 Data Link layer — manages DLSM instances for connected-mode links.
class Ax25Link {
  Ax25Dlsm? _listHead;
  RegCallsign? _regCallsignList;
  int _nextStreamId = 0;

  // Debug switches
  bool debugProtocolErrors = false;
  bool debugClientApp = false;
  bool debugRadio = false;
  bool debugVariables = false;
  bool debugRetry = false;
  bool debugTimers = false;
  bool debugLinkHandle = false;
  bool debugStats = false;
  bool debugMisc = false;

  late MiscConfig _config;

  // DCD and PTT status per channel
  final List<bool> _dcdStatus = List.filled(16, false);
  final List<bool> _pttStatus = List.filled(16, false);

  /// Callback when a connection is established.
  void Function(Ax25Dlsm s)? onConnectionEstablished;

  /// Callback when a connection is terminated.
  void Function(Ax25Dlsm s)? onConnectionTerminated;

  /// Callback when data is received.
  void Function(Ax25Dlsm s, int pid, List<int> data, int len)?
      onDataIndication;

  /// Initialize the AX.25 link module.
  void init(MiscConfig config, {int debug = 0}) {
    _config = config;

    if (debug >= 1) {
      debugProtocolErrors = true;
      debugClientApp = true;
      debugRadio = true;
      debugVariables = true;
      debugRetry = true;
      debugLinkHandle = true;
      debugStats = true;
      debugMisc = true;
      debugTimers = true;
    }
  }

  // =========================================================================
  // HELPER FUNCTIONS
  // =========================================================================

  int _ax25Modulo(int n, int m) {
    if (m != 8 && m != 128) m = 8;
    return n & (m - 1);
  }

  bool _withinWindowSize(Ax25Dlsm s) {
    return s.vs != _ax25Modulo(s.va + s.kMaxframe, s.modulo);
  }

  void _setVs(Ax25Dlsm s, int n) {
    s.vs = n;
    assert(s.vs >= 0 && s.vs < s.modulo);
  }

  void _setVa(Ax25Dlsm s, int n) {
    s.va = n;
    assert(s.va >= 0 && s.va < s.modulo);
    // Clear out acknowledged frames
    int x = _ax25Modulo(n - 1, s.modulo);
    while (s.txdataByNs[x] != null) {
      s.txdataByNs[x] = null;
      x = _ax25Modulo(x - 1, s.modulo);
    }
  }

  void _setVr(Ax25Dlsm s, int n) {
    s.vr = n;
    assert(s.vr >= 0 && s.vr < s.modulo);
  }

  void _setRc(Ax25Dlsm s, int n) {
    s.rc = n;
  }

  void _enterNewState(Ax25Dlsm s, DlsmState newState) {
    s.state = newState;
  }

  void _initT1vSrt(Ax25Dlsm s) {
    s.t1v = _config.frack * (2 * (s.numAddr - 2) + 1);
    s.srt = s.t1v / 2.0;
  }

  // =========================================================================
  // TIMER FUNCTIONS
  // =========================================================================

  void _startT1(Ax25Dlsm s) {
    final now = _getTime();
    s.t1Exp = now + s.t1v;
    s.t1PausedAt = s.radioChannelBusy ? now : 0;
    s.t1HadExpired = false;
  }

  void _stopT1(Ax25Dlsm s) {
    final now = _getTime();
    _resumeT1(s);
    if (s.t1Exp != 0) {
      s.t1RemainingWhenLastStopped = s.t1Exp - now;
      if (s.t1RemainingWhenLastStopped < 0) {
        s.t1RemainingWhenLastStopped = 0;
      }
    }
    s.t1Exp = 0;
    s.t1HadExpired = false;
  }

  bool _isT1Running(Ax25Dlsm s) => s.t1Exp != 0;

  void _pauseT1(Ax25Dlsm s) {
    if (s.t1Exp != 0 && s.t1PausedAt == 0) {
      s.t1PausedAt = _getTime();
    }
  }

  void _resumeT1(Ax25Dlsm s) {
    if (s.t1Exp != 0 && s.t1PausedAt != 0) {
      final now = _getTime();
      s.t1Exp += (now - s.t1PausedAt);
      s.t1PausedAt = 0;
    }
  }

  void _startT3(Ax25Dlsm s) {
    s.t3Exp = _getTime() + Ax25LinkConstants.t3Default;
  }

  void _stopT3(Ax25Dlsm s) {
    s.t3Exp = 0;
  }

  void _startTm201(Ax25Dlsm s) {
    final now = _getTime();
    s.tm201Exp = now + s.t1v;
    s.tm201PausedAt = s.radioChannelBusy ? now : 0;
  }

  void _stopTm201(Ax25Dlsm s) {
    s.tm201Exp = 0;
  }

  void _pauseTm201(Ax25Dlsm s) {
    if (s.tm201Exp != 0 && s.tm201PausedAt == 0) {
      s.tm201PausedAt = _getTime();
    }
  }

  void _resumeTm201(Ax25Dlsm s) {
    if (s.tm201Exp != 0 && s.tm201PausedAt != 0) {
      final now = _getTime();
      s.tm201Exp += (now - s.tm201PausedAt);
      s.tm201PausedAt = 0;
    }
  }

  // =========================================================================
  // TIMER EXPIRY
  // =========================================================================

  /// Check and process timer expiries. Call this periodically.
  void dlTimerExpiry() {
    final now = _getTime();

    // T1 expiry
    var p = _listHead;
    while (p != null) {
      final pNext = p.next;
      if (p.t1Exp != 0 && p.t1PausedAt == 0 && p.t1Exp <= now) {
        p.t1Exp = 0;
        p.t1PausedAt = 0;
        p.t1HadExpired = true;
        _t1Expiry(p);
      }
      p = pNext;
    }

    // T3 expiry
    p = _listHead;
    while (p != null) {
      final pNext = p.next;
      if (p.t3Exp != 0 && p.t3Exp <= now) {
        p.t3Exp = 0;
        _t3Expiry(p);
      }
      p = pNext;
    }

    // TM201 expiry
    p = _listHead;
    while (p != null) {
      final pNext = p.next;
      if (p.tm201Exp != 0 && p.tm201PausedAt == 0 && p.tm201Exp <= now) {
        p.tm201Exp = 0;
        p.tm201PausedAt = 0;
        _tm201Expiry(p);
      }
      p = pNext;
    }
  }

  void _t1Expiry(Ax25Dlsm s) {
    switch (s.state) {
      case DlsmState.disconnected:
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (s.state == DlsmState.awaitingV22Connection &&
            s.rc == _config.maxv22) {
          _setVersion20(s);
          _enterNewState(s, DlsmState.awaitingConnection);
        }
        if (s.rc == s.n2Retry) {
          _discardIQueue(s);
          _enterNewState(s, DlsmState.disconnected);
          _dlConnectionTerminated(s);
        } else {
          _setRc(s, s.rc + 1);
          if (s.rc > s.peakRcValue) s.peakRcValue = s.rc;
          _selectT1Value(s);
          _startT1(s);
        }
        break;

      case DlsmState.awaitingRelease:
        if (s.rc == s.n2Retry) {
          _enterNewState(s, DlsmState.disconnected);
          _dlConnectionTerminated(s);
        } else {
          _setRc(s, s.rc + 1);
          if (s.rc > s.peakRcValue) s.peakRcValue = s.rc;
          _selectT1Value(s);
          _startT1(s);
        }
        break;

      case DlsmState.connected:
        _setRc(s, 1);
        _transmitEnquiry(s);
        _enterNewState(s, DlsmState.timerRecovery);
        break;

      case DlsmState.timerRecovery:
        if (s.rc == s.n2Retry) {
          _discardIQueue(s);
          _enterNewState(s, DlsmState.disconnected);
          _dlConnectionTerminated(s);
        } else {
          _setRc(s, s.rc + 1);
          if (s.rc > s.peakRcValue) s.peakRcValue = s.rc;
          _transmitEnquiry(s);
        }
        break;
    }
  }

  void _t3Expiry(Ax25Dlsm s) {
    switch (s.state) {
      case DlsmState.connected:
        _setRc(s, 1);
        _transmitEnquiry(s);
        _enterNewState(s, DlsmState.timerRecovery);
        break;
      default:
        break;
    }
  }

  void _tm201Expiry(Ax25Dlsm s) {
    switch (s.mdlState) {
      case MdlState.ready:
        break;
      case MdlState.negotiating:
        s.mdlRc++;
        if (s.mdlRc > s.n2Retry) {
          s.mdlState = MdlState.ready;
        } else {
          _startTm201(s);
        }
        break;
    }
  }

  /// Get next timer expiry time (0 = none).
  double getNextTimerExpiry() {
    double tnext = 0;
    for (var p = _listHead; p != null; p = p.next) {
      if (p.t1Exp != 0 && p.t1PausedAt == 0) {
        if (tnext == 0 || p.t1Exp < tnext) tnext = p.t1Exp;
      }
      if (p.t3Exp != 0) {
        if (tnext == 0 || p.t3Exp < tnext) tnext = p.t3Exp;
      }
      if (p.tm201Exp != 0 && p.tm201PausedAt == 0) {
        if (tnext == 0 || p.tm201Exp < tnext) tnext = p.tm201Exp;
      }
    }
    return tnext;
  }

  // =========================================================================
  // LINK MANAGEMENT
  // =========================================================================

  Ax25Dlsm? _getLinkHandle(
      List<String> addrs, int numAddr, int chan, int client, bool create) {
    // Look for existing
    if (client == -1) {
      // From radio
      for (var p = _listHead; p != null; p = p.next) {
        if (p.chan == chan &&
            addrs[1].toUpperCase() == p.addrs[Ax25Dlsm.ownCall].toUpperCase() &&
            addrs[0].toUpperCase() ==
                p.addrs[Ax25Dlsm.peerCall].toUpperCase()) {
          return p;
        }
      }
    } else {
      // From client app
      for (var p = _listHead; p != null; p = p.next) {
        if (p.chan == chan &&
            p.client == client &&
            addrs[0].toUpperCase() == p.addrs[Ax25Dlsm.ownCall].toUpperCase() &&
            addrs[1].toUpperCase() ==
                p.addrs[Ax25Dlsm.peerCall].toUpperCase()) {
          return p;
        }
      }
    }

    if (!create) return null;

    // Check registered callsigns if from radio
    int incomingForClient = -1;
    if (client == -1) {
      RegCallsign? found;
      for (var r = _regCallsignList; r != null && found == null; r = r.next) {
        if (addrs[1].toUpperCase() == r.callsign.toUpperCase() &&
            chan == r.chan) {
          found = r;
          incomingForClient = r.client;
        }
      }
      if (found == null) return null; // Not for me
    }

    // Create new DLSM
    final newS = Ax25Dlsm(
      streamId: _nextStreamId++,
      chan: chan,
    )
      ..numAddr = numAddr
      ..t1RemainingWhenLastStopped = -999;

    if (incomingForClient >= 0) {
      // Swap source/dest and reverse digi path for incoming
      newS.addrs[0] = addrs[1];
      newS.addrs[1] = addrs[0];
      int j = 2;
      int k = numAddr - 1;
      while (k >= 2) {
        newS.addrs[j] = addrs[k];
        j++;
        k--;
      }
      newS.client = incomingForClient;
    } else {
      for (int i = 0; i < numAddr; i++) {
        newS.addrs[i] = addrs[i];
      }
      newS.client = client;
    }

    // Add to list
    newS.next = _listHead;
    _listHead = newS;

    return newS;
  }

  void _dlConnectionCleanup(Ax25Dlsm s) {
    _discardIQueue(s);
    for (int n = 0; n < 128; n++) {
      s.txdataByNs[n] = null;
      s.rxdataByNs[n] = null;
    }
    s.raBuff = null;
    _enterNewState(s, DlsmState.disconnected);
  }

  void _dlConnectionTerminated(Ax25Dlsm s) {
    // Remove from list
    Ax25Dlsm? dlprev;
    Ax25Dlsm? dlentry = _listHead;
    while (dlentry != null && !identical(dlentry, s)) {
      dlprev = dlentry;
      dlentry = dlentry.next;
    }

    if (dlprev == null) {
      _listHead = dlentry?.next;
    } else {
      dlprev.next = dlentry?.next;
    }

    _dlConnectionCleanup(s);
    onConnectionTerminated?.call(s);
  }

  // =========================================================================
  // UTILITY FUNCTIONS
  // =========================================================================

  void _discardIQueue(Ax25Dlsm s) {
    s.iFrameQueue = null;
  }

  void _clearExceptionConditions(Ax25Dlsm s) {
    s.peerReceiverBusy = false;
    s.rejectException = false;
    s.ownReceiverBusy = false;
    s.acknowledgePending = false;
    for (int n = 0; n < 128; n++) {
      s.rxdataByNs[n] = null;
    }
  }

  void _establishDataLink(Ax25Dlsm s) {
    _clearExceptionConditions(s);
    _setRc(s, 1);
    _stopT3(s);
    _startT1(s);
  }

  void _setVersion20(Ax25Dlsm s) {
    s.srejEnable = SrejEnable.none;
    s.modulo = 8;
    s.n1Paclen = _config.paclen;
    s.kMaxframe = _config.maxframeBasic;
    s.n2Retry = _config.retry;
  }

  void _setVersion22(Ax25Dlsm s) {
    s.srejEnable = SrejEnable.single;
    s.modulo = 128;
    s.n1Paclen = _config.paclen;
    s.kMaxframe = _config.maxframeExtended;
    s.n2Retry = _config.retry;
  }

  void _transmitEnquiry(Ax25Dlsm s) {
    // Would send RR or RNR command with P=1 here
    s.acknowledgePending = false;
    _startT1(s);
  }

  void _selectT1Value(Ax25Dlsm s) {
    if (s.rc == 0) {
      if (s.t1RemainingWhenLastStopped >= 0) {
        s.srt = 7.0 / 8.0 * s.srt +
            1.0 / 8.0 * (s.t1v - s.t1RemainingWhenLastStopped);
      }
      if (s.srt < 1) {
        s.srt = 1;
        if (s.numAddr > 2) s.srt += 2 * (s.numAddr - 2);
      }
      s.t1v = s.srt * 2;
    } else {
      if (s.t1HadExpired) {
        s.t1v = s.rc * 0.25 + s.srt * 2;
      }
    }

    // Guardrails
    final maxT1v = 2 * (_config.frack * (2 * (s.numAddr - 2) + 1));
    if (s.t1v < 0.25 || s.t1v > maxT1v) {
      _initT1vSrt(s);
    }
  }

  bool _isGoodNr(Ax25Dlsm s, int nr) {
    final adjustedNr = _ax25Modulo(nr - s.va, s.modulo);
    final adjustedVs = _ax25Modulo(s.vs - s.va, s.modulo);
    return 0 <= adjustedNr && adjustedNr <= adjustedVs;
  }

  void _iFramePopOffQueue(Ax25Dlsm s) {
    if (s.iFrameQueue == null) return;

    switch (s.state) {
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (s.layerThreeInitiated) {
          s.iFrameQueue = s.iFrameQueue?.next; // Discard
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        while (!s.peerReceiverBusy &&
            s.iFrameQueue != null &&
            _withinWindowSize(s)) {
          final txdata = s.iFrameQueue!;
          s.iFrameQueue = txdata.next;
          txdata.next = null;

          final ns = s.vs;
          s.txdataByNs[ns] = txdata;
          _setVs(s, _ax25Modulo(s.vs + 1, s.modulo));
          s.acknowledgePending = false;
          _stopT3(s);
          _startT1(s);
        }
        break;

      case DlsmState.disconnected:
      case DlsmState.awaitingRelease:
        break;
    }
  }

  void _checkIFrameAckd(Ax25Dlsm s, int nr) {
    if (s.peerReceiverBusy) {
      _setVa(s, nr);
      _startT3(s);
      if (!_isT1Running(s)) _startT1(s);
    } else if (nr == s.vs) {
      _setVa(s, nr);
      _stopT1(s);
      _startT3(s);
      _selectT1Value(s);
    } else if (nr != s.va) {
      _setVa(s, nr);
      _startT1(s);
    }
  }

  void _nrErrorRecovery(Ax25Dlsm s) {
    _establishDataLink(s);
    s.layerThreeInitiated = false;
  }

  void _enquiryResponse(Ax25Dlsm s, int frameType, int f) {
    // Would send RR or RNR response with F bit here
    s.acknowledgePending = false;
  }

  void _checkNeedForResponse(
      Ax25Dlsm s, int frameType, bool isCommand, int pf) {
    if (isCommand && pf == 1) {
      _enquiryResponse(s, frameType, 1);
    }
  }

  void _invokeRetransmission(Ax25Dlsm s, int nrInput) {
    if (s.txdataByNs[nrInput] == null) return;

    int localVs = nrInput;
    do {
      // Would construct and send I frame with N(S)=localVs, N(R)=s.vr, P=0
      localVs = _ax25Modulo(localVs + 1, s.modulo);
    } while (localVs != s.vs);
  }

  bool _isNsInWindow(Ax25Dlsm s, int ns) {
    final adjustedNs = _ax25Modulo(ns - s.vr, s.modulo);
    final adjustedVrpk =
        _ax25Modulo(s.vr + Ax25LinkConstants.generousK - s.vr, s.modulo);
    return 0 < adjustedNs && adjustedNs < adjustedVrpk;
  }

  void _dlDataIndication(Ax25Dlsm s, int pid, List<int> data, int len) {
    onDataIndication?.call(s, pid, data, len);
  }

  // =========================================================================
  // PUBLIC API
  // =========================================================================

  /// Request a connection to a remote station.
  void dlConnectRequest(
      List<String> addrs, int numAddr, int chan, int client) {
    final s = _getLinkHandle(addrs, numAddr, chan, client, true);
    if (s == null) return;

    switch (s.state) {
      case DlsmState.disconnected:
        _initT1vSrt(s);
        bool oldVersion = _config.v20Addrs.any(
            (v) => v.toUpperCase() == addrs[1].toUpperCase());

        if (oldVersion || _config.maxv22 == 0) {
          _setVersion20(s);
          _establishDataLink(s);
          s.layerThreeInitiated = true;
          _enterNewState(s, DlsmState.awaitingConnection);
        } else {
          _setVersion22(s);
          _establishDataLink(s);
          s.layerThreeInitiated = true;
          _enterNewState(s, DlsmState.awaitingV22Connection);
        }
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        _discardIQueue(s);
        s.layerThreeInitiated = true;
        break;

      case DlsmState.awaitingRelease:
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);
        _establishDataLink(s);
        s.layerThreeInitiated = true;
        _enterNewState(
            s,
            s.modulo == 128
                ? DlsmState.awaitingV22Connection
                : DlsmState.awaitingConnection);
        break;
    }
  }

  /// Request disconnection from a remote station.
  void dlDisconnectRequest(
      List<String> addrs, int numAddr, int chan, int client) {
    final s = _getLinkHandle(addrs, numAddr, chan, client, true);
    if (s == null) return;

    switch (s.state) {
      case DlsmState.disconnected:
        _enterNewState(s, DlsmState.disconnected);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        _discardIQueue(s);
        _setRc(s, 0);
        _stopT1(s);
        _stopT3(s);
        _enterNewState(s, DlsmState.disconnected);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.awaitingRelease:
        _stopT1(s);
        _enterNewState(s, DlsmState.disconnected);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);
        _setRc(s, 0);
        _stopT3(s);
        _startT1(s);
        _enterNewState(s, DlsmState.awaitingRelease);
        break;
    }
  }

  /// Queue data for transmission.
  void dlDataRequest(
      List<String> addrs, int numAddr, int chan, int client, CData txdata) {
    final s = _getLinkHandle(addrs, numAddr, chan, client, true);
    if (s == null) return;

    if (txdata.len > s.n1Paclen) {
      // Segmentation
      int offset = 0;
      int remaining = txdata.len;
      while (remaining > 0) {
        final thisLen = min(remaining, s.n1Paclen);
        final dataSlice = txdata.data.sublist(offset, offset + thisLen);
        final newTxdata = CData(txdata.pid, dataSlice, thisLen);
        _dataRequestGoodSize(s, newTxdata);
        offset += thisLen;
        remaining -= thisLen;
      }
      return;
    }
    _dataRequestGoodSize(s, txdata);
  }

  void _dataRequestGoodSize(Ax25Dlsm s, CData txdata) {
    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingRelease:
        break; // Discard

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (!s.layerThreeInitiated) {
          _appendToIQueue(s, txdata);
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _appendToIQueue(s, txdata);
        break;
    }

    if ((s.state == DlsmState.connected ||
            s.state == DlsmState.timerRecovery) &&
        !s.peerReceiverBusy &&
        _withinWindowSize(s)) {
      s.acknowledgePending = true;
    }
  }

  void _appendToIQueue(Ax25Dlsm s, CData txdata) {
    if (s.iFrameQueue == null) {
      txdata.next = null;
      s.iFrameQueue = txdata;
    } else {
      var plast = s.iFrameQueue!;
      while (plast.next != null) {
        plast = plast.next!;
      }
      txdata.next = null;
      plast.next = txdata;
    }
  }

  /// Register a callsign for incoming connections.
  void dlRegisterCallsign(String callsign, int chan, int client) {
    final r = RegCallsign(callsign, chan, client)..next = _regCallsignList;
    _regCallsignList = r;
  }

  /// Unregister a callsign.
  void dlUnregisterCallsign(String callsign, int chan, int client) {
    RegCallsign? prev;
    var r = _regCallsignList;
    while (r != null) {
      if (r.callsign.toUpperCase() == callsign.toUpperCase() &&
          r.chan == chan &&
          r.client == client) {
        if (identical(r, _regCallsignList)) {
          _regCallsignList = r.next;
          r = _regCallsignList;
        } else {
          prev?.next = r.next;
          r = prev?.next;
        }
      } else {
        prev = r;
        r = r.next;
      }
    }
  }

  /// Clean up all state for a client.
  void dlClientCleanup(int client) {
    Ax25Dlsm? dlprev;
    var s = _listHead;
    while (s != null) {
      if (s.client == client) {
        if (identical(s, _listHead)) {
          _listHead = s.next;
          _dlConnectionCleanup(s);
          s = _listHead;
        } else {
          dlprev?.next = s.next;
          _dlConnectionCleanup(s);
          s = dlprev?.next;
        }
      } else {
        dlprev = s;
        s = s.next;
      }
    }

    RegCallsign? rcprev;
    var r = _regCallsignList;
    while (r != null) {
      if (r.client == client) {
        if (identical(r, _regCallsignList)) {
          _regCallsignList = r.next;
          r = _regCallsignList;
        } else {
          rcprev?.next = r.next;
          r = rcprev?.next;
        }
      } else {
        rcprev = r;
        r = r.next;
      }
    }
  }

  // =========================================================================
  // CHANNEL BUSY MANAGEMENT
  // =========================================================================

  /// Notify the link layer of DCD/PTT state changes.
  void lmChannelBusy(int chan, bool isDcd, bool status) {
    assert(chan >= 0 && chan < 16);

    if (isDcd) {
      _dcdStatus[chan] = status;
    } else {
      _pttStatus[chan] = status;
    }

    final busy = _dcdStatus[chan] || _pttStatus[chan];

    for (var s = _listHead; s != null; s = s.next) {
      if (chan == s.chan) {
        if (busy && !s.radioChannelBusy) {
          s.radioChannelBusy = true;
          _pauseT1(s);
          _pauseTm201(s);
        } else if (!busy && s.radioChannelBusy) {
          s.radioChannelBusy = false;
          _resumeT1(s);
          _resumeTm201(s);
        }
      }
    }
  }

  /// Channel clear for transmission — kick off pending I frames.
  void lmSeizeConfirm(int chan) {
    for (var s = _listHead; s != null; s = s.next) {
      if (chan == s.chan) {
        switch (s.state) {
          case DlsmState.connected:
          case DlsmState.timerRecovery:
            _iFramePopOffQueue(s);
            if (s.acknowledgePending) {
              s.acknowledgePending = false;
              _enquiryResponse(s, 0, 0);
            }
            break;
          default:
            break;
        }
      }
    }
  }

  // =========================================================================
  // FRAME RECEPTION
  // =========================================================================

  /// Process a received SABM or SABME frame.
  void processSabmFrame(Ax25Dlsm s, bool extended, int p) {
    switch (s.state) {
      case DlsmState.disconnected:
        if (extended) {
          _setVersion22(s);
        } else {
          _setVersion20(s);
        }
        _clearExceptionConditions(s);
        _setVs(s, 0);
        _setVa(s, 0);
        _setVr(s, 0);
        _initT1vSrt(s);
        _startT3(s);
        _setRc(s, 0);
        _enterNewState(s, DlsmState.connected);
        onConnectionEstablished?.call(s);
        break;

      case DlsmState.awaitingConnection:
        if (extended) {
          _enterNewState(s, DlsmState.awaitingV22Connection);
        }
        break;

      case DlsmState.awaitingV22Connection:
        if (!extended) {
          _enterNewState(s, DlsmState.awaitingConnection);
        }
        break;

      case DlsmState.awaitingRelease:
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        if (s.state == DlsmState.timerRecovery) {
          if (extended) {
            _setVersion22(s);
          } else {
            _setVersion20(s);
          }
        }
        _clearExceptionConditions(s);
        if (s.vs != s.va) {
          _discardIQueue(s);
          onConnectionEstablished?.call(s);
        }
        _stopT1(s);
        _startT3(s);
        _setVs(s, 0);
        _setVa(s, 0);
        _setVr(s, 0);
        _setRc(s, 0);
        _enterNewState(s, DlsmState.connected);
        break;
    }
  }

  /// Process a received DISC frame.
  void processDiscFrame(Ax25Dlsm s, int p) {
    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
      case DlsmState.awaitingRelease:
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);
        _stopT1(s);
        _stopT3(s);
        _enterNewState(s, DlsmState.disconnected);
        _dlConnectionTerminated(s);
        break;
    }
  }

  /// Process a received UA frame.
  void processUaFrame(Ax25Dlsm s, int f) {
    switch (s.state) {
      case DlsmState.disconnected:
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (f == 1) {
          _stopT1(s);
          _startT3(s);
          _setVs(s, 0);
          _setVa(s, 0);
          _setVr(s, 0);
          _selectT1Value(s);
          _setRc(s, 0);
          _enterNewState(s, DlsmState.connected);
          onConnectionEstablished?.call(s);
        }
        break;

      case DlsmState.awaitingRelease:
        if (f == 1) {
          _stopT1(s);
          _enterNewState(s, DlsmState.disconnected);
          _dlConnectionTerminated(s);
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _establishDataLink(s);
        s.layerThreeInitiated = false;
        _enterNewState(
            s,
            s.modulo == 128
                ? DlsmState.awaitingV22Connection
                : DlsmState.awaitingConnection);
        break;
    }
  }

  /// Process a received DM frame.
  void processDmFrame(Ax25Dlsm s, int f) {
    switch (s.state) {
      case DlsmState.disconnected:
        break;

      case DlsmState.awaitingConnection:
        if (f == 1) {
          _discardIQueue(s);
          _stopT1(s);
          _enterNewState(s, DlsmState.disconnected);
          _dlConnectionTerminated(s);
        }
        break;

      case DlsmState.awaitingRelease:
        if (f == 1) {
          _stopT1(s);
          _enterNewState(s, DlsmState.disconnected);
          _dlConnectionTerminated(s);
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);
        _stopT1(s);
        _stopT3(s);
        _enterNewState(s, DlsmState.disconnected);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.awaitingV22Connection:
        if (f == 1) {
          _initT1vSrt(s);
          _setVersion20(s);
          _establishDataLink(s);
          s.layerThreeInitiated = true;
          _enterNewState(s, DlsmState.awaitingConnection);
        }
        break;
    }
  }

  /// Process a received FRMR frame.
  void processFrmrFrame(Ax25Dlsm s) {
    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingRelease:
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _setVersion20(s);
        _establishDataLink(s);
        s.layerThreeInitiated = false;
        _enterNewState(s, DlsmState.awaitingConnection);
        break;

      case DlsmState.awaitingV22Connection:
        _initT1vSrt(s);
        _setVersion20(s);
        _establishDataLink(s);
        s.layerThreeInitiated = true;
        _enterNewState(s, DlsmState.awaitingConnection);
        break;
    }
  }
}
