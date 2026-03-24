/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

// Protocol: Kenwood TS-2000 CAT (Computer Aided Transceiver)
// Commands are ASCII, semicolon-terminated, 9600 8N1
// Primary use: VaraFM PTT control over virtual serial port (PTY)

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';

// --- PTY FFI bindings ---

typedef _PosixOpenptNative = Int32 Function(Int32 flags);
typedef _PosixOpenptDart = int Function(int flags);

typedef _GrantptNative = Int32 Function(Int32 fd);
typedef _GrantptDart = int Function(int fd);

typedef _UnlockptNative = Int32 Function(Int32 fd);
typedef _UnlockptDart = int Function(int fd);

typedef _PtsnameNative = Pointer<Utf8> Function(Int32 fd);
typedef _PtsnameDart = Pointer<Utf8> Function(int fd);

typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);

typedef _ReadNative = Int64 Function(Int32 fd, Pointer<Void> buf, Int64 count);
typedef _ReadDart = int Function(int fd, Pointer<Void> buf, int count);

typedef _WriteNative = Int64 Function(
    Int32 fd, Pointer<Void> buf, Int64 count);
typedef _WriteDart = int Function(int fd, Pointer<Void> buf, int count);

typedef _Fcntl3Native = Int32 Function(Int32 fd, Int32 cmd, Int32 arg);
typedef _Fcntl3Dart = int Function(int fd, int cmd, int arg);

typedef _ErrnoLocationNative = Pointer<Int32> Function();
typedef _ErrnoLocationDart = Pointer<Int32> Function();

/// O_RDWR | O_NOCTTY for posix_openpt.
const int _oRdwr = 2;
const int _oNoctty = 256;
const int _oNonblock = 0x800;
const int _fSetfl = 4;

/// Native libc bindings for PTY operations.
class _PtyNative {
  _PtyNative._();

  static final DynamicLibrary _libc = DynamicLibrary.open('libc.so.6');

  static final int Function(int flags) posixOpenpt =
      _libc.lookupFunction<_PosixOpenptNative, _PosixOpenptDart>(
          'posix_openpt');

  static final int Function(int fd) grantpt =
      _libc.lookupFunction<_GrantptNative, _GrantptDart>('grantpt');

  static final int Function(int fd) unlockpt =
      _libc.lookupFunction<_UnlockptNative, _UnlockptDart>('unlockpt');

  static final Pointer<Utf8> Function(int fd) ptsname =
      _libc.lookupFunction<_PtsnameNative, _PtsnameDart>('ptsname');

  static final int Function(int fd) close =
      _libc.lookupFunction<_CloseNative, _CloseDart>('close');

  static final int Function(int fd, Pointer<Void> buf, int count) read =
      _libc.lookupFunction<_ReadNative, _ReadDart>('read');

  static final int Function(int fd, Pointer<Void> buf, int count) write =
      _libc.lookupFunction<_WriteNative, _WriteDart>('write');

  static final int Function(int fd, int cmd, int arg) fcntl3 =
      _libc.lookupFunction<_Fcntl3Native, _Fcntl3Dart>('fcntl');

  static final _ErrnoLocationDart _errnoLocation =
      _libc.lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>(
          '__errno_location');

  static int get errno => _errnoLocation().value;
}

/// Virtual COM port emulating a Kenwood TS-2000 for CAT control.
///
/// Primary path for VaraFM PTT. Creates a Linux PTY pair: the master fd is
/// used internally, the slave device path (e.g. /dev/pts/3) is exposed to
/// external applications.
///
/// Port of HTCommander.Core/Utils/CatSerialServer.cs
class CatSerialServer {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _running = false;
  bool _pttActive = false;
  Timer? _pttSilenceTimer;
  Timer? _pttTimeoutTimer;
  static const int _pttTimeoutMs = 30000;
  int _cachedFrequencyA = 145500000;
  int _cachedFrequencyB = 145500000;
  int _activeRadioId = -1;
  bool _autoInfo = false;
  final StringBuffer _commandBuffer = StringBuffer();
  static const int _maxBufferLength = 1024;

  // PTY state
  int _masterFd = -1;
  String _slavePath = '';
  Timer? _readTimer;
  Pointer<Void>? _readBuf;

  bool get pttActive => _pttActive;

  CatSerialServer() {
    _broker.subscribe(0, 'CatServerEnabled', _onSettingChanged);
    _broker.subscribe(1, 'ConnectedRadios', _onConnectedRadiosChanged);
    _broker.subscribe(DataBroker.allDevices, 'Settings', _onSettingsChanged);

    final enabled = _broker.getValue<int>(0, 'CatServerEnabled', 0);
    if (enabled == 1) {
      _start();
    }
  }

  void _onSettingChanged(int deviceId, String name, Object? data) {
    final enabled = _broker.getValue<int>(0, 'CatServerEnabled', 0);
    if (enabled == 1 && !_running) {
      _start();
    } else if (enabled != 1 && _running) {
      _stop();
    }
  }

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    _activeRadioId = _getFirstConnectedRadioId();
  }

  void _onSettingsChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100) return;
    if (data is Map) {
      final freqA = data['vfo1_mod_freq_x'];
      if (freqA is int && freqA > 0) _cachedFrequencyA = freqA;
      final freqB = data['vfo2_mod_freq_x'];
      if (freqB is int && freqB > 0) _cachedFrequencyB = freqB;
    }
  }

  void _start() {
    if (_running) return;
    if (!Platform.isLinux) {
      _log('CAT server: only supported on Linux');
      return;
    }

    // Create PTY pair via libc
    final masterFd = _PtyNative.posixOpenpt(_oRdwr | _oNoctty);
    if (masterFd < 0) {
      _log('CAT server: posix_openpt failed (errno ${_PtyNative.errno})');
      return;
    }

    if (_PtyNative.grantpt(masterFd) != 0) {
      _log('CAT server: grantpt failed (errno ${_PtyNative.errno})');
      _PtyNative.close(masterFd);
      return;
    }

    if (_PtyNative.unlockpt(masterFd) != 0) {
      _log('CAT server: unlockpt failed (errno ${_PtyNative.errno})');
      _PtyNative.close(masterFd);
      return;
    }

    final ptsnamePtr = _PtyNative.ptsname(masterFd);
    if (ptsnamePtr == nullptr) {
      _log('CAT server: ptsname failed (errno ${_PtyNative.errno})');
      _PtyNative.close(masterFd);
      return;
    }

    final slavePath = ptsnamePtr.toDartString();

    // Set master fd to non-blocking for polling reads
    _PtyNative.fcntl3(masterFd, _fSetfl, _oNonblock);

    _masterFd = masterFd;
    _slavePath = slavePath;
    _running = true;

    // Allocate read buffer (reused across reads)
    _readBuf = calloc<Uint8>(1024).cast<Void>();

    // Poll for incoming data every 20ms
    _readTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _pollRead();
    });

    _log('CAT server started on $slavePath');
    _broker.dispatch(1, 'CatPortPath', slavePath, store: false);

    // Create a symlink at a well-known path for convenience
    _createSymlink(slavePath);
  }

  void _stop() {
    if (!_running) return;
    _log('CAT server stopping...');
    _running = false;
    _setPtt(false);

    _readTimer?.cancel();
    _readTimer = null;

    if (_readBuf != null) {
      calloc.free(_readBuf!.cast<Uint8>());
      _readBuf = null;
    }

    if (_masterFd >= 0) {
      _PtyNative.close(_masterFd);
      _masterFd = -1;
    }

    _removeSymlink();
    _slavePath = '';
    _commandBuffer.clear();

    _broker.dispatch(1, 'CatPortPath', '', store: false);
    _log('CAT server stopped');
  }

  /// Creates a symlink at /tmp/htcommander-cat → slave PTY path.
  void _createSymlink(String slavePath) {
    try {
      final link = Link('/tmp/htcommander-cat');
      if (link.existsSync()) link.deleteSync();
      link.createSync(slavePath);
      _log('CAT symlink: /tmp/htcommander-cat → $slavePath');
    } catch (e) {
      _log('CAT symlink creation failed: $e');
    }
  }

  void _removeSymlink() {
    try {
      final link = Link('/tmp/htcommander-cat');
      if (link.existsSync()) link.deleteSync();
    } catch (_) {}
  }

  /// Polls the master PTY fd for incoming data (non-blocking).
  void _pollRead() {
    if (!_running || _masterFd < 0 || _readBuf == null) return;

    // Read in a loop to drain available data
    while (true) {
      final n = _PtyNative.read(_masterFd, _readBuf!, 1024);
      if (n <= 0) break; // EAGAIN or error

      final bytes =
          _readBuf!.cast<Uint8>().asTypedList(n);
      final text = ascii.decode(bytes, allowInvalid: true);
      _onDataReceived(text);
    }
  }

  void _onDataReceived(String text) {
    _commandBuffer.write(text);

    // Prevent unbounded buffer growth
    if (_commandBuffer.length > _maxBufferLength) {
      _commandBuffer.clear();
      return;
    }

    // Process complete commands (semicolon-terminated)
    var buffer = _commandBuffer.toString();
    int semicolon;
    while ((semicolon = buffer.indexOf(';')) >= 0) {
      final cmd = buffer.substring(0, semicolon);
      buffer = buffer.substring(semicolon + 1);
      _processCommand(cmd);
    }
    _commandBuffer.clear();
    if (buffer.isNotEmpty) _commandBuffer.write(buffer);
  }

  void _processCommand(String cmd) {
    if (cmd.isEmpty) return;

    late String response;

    // TX command (PTT ON)
    if (cmd == 'TX' || cmd == 'TX0' || cmd == 'TX1' || cmd == 'TX2') {
      _setPtt(true);
      response = '$cmd;';
    }
    // RX command (PTT OFF)
    else if (cmd == 'RX') {
      _setPtt(false);
      response = 'RX;';
    }
    // Get/Set VFO A frequency
    else if (cmd == 'FA') {
      response = 'FA${_cachedFrequencyA.toString().padLeft(11, '0')};';
    } else if (cmd.startsWith('FA') && cmd.length > 2) {
      final freq = int.tryParse(cmd.substring(2));
      if (freq != null && freq > 0 && freq <= 2147483647) {
        _cachedFrequencyA = freq;
        _setRadioFrequency(freq, 'A');
      }
      response = 'FA${_cachedFrequencyA.toString().padLeft(11, '0')};';
    }
    // Get/Set VFO B frequency
    else if (cmd == 'FB') {
      response = 'FB${_cachedFrequencyB.toString().padLeft(11, '0')};';
    } else if (cmd.startsWith('FB') && cmd.length > 2) {
      final freq = int.tryParse(cmd.substring(2));
      if (freq != null && freq > 0 && freq <= 2147483647) {
        _cachedFrequencyB = freq;
        _setRadioFrequency(freq, 'B');
      }
      response = 'FB${_cachedFrequencyB.toString().padLeft(11, '0')};';
    }
    // Get mode (always FM = 4)
    else if (cmd == 'MD') {
      response = 'MD4;';
    } else if (cmd.startsWith('MD') && cmd.length > 2) {
      response = 'MD4;'; // Always FM
    }
    // IF — transceiver info
    else if (cmd == 'IF') {
      response = _buildIfResponse();
    }
    // ID — radio identification (TS-2000 = 019)
    else if (cmd == 'ID') {
      response = 'ID019;';
    }
    // Auto-info
    else if (cmd == 'AI0') {
      _autoInfo = false;
      response = 'AI0;';
    } else if (cmd == 'AI1') {
      _autoInfo = true;
      response = 'AI1;';
    } else if (cmd == 'AI') {
      response = _autoInfo ? 'AI1;' : 'AI0;';
    }
    // Power status
    else if (cmd == 'PS') {
      response = 'PS1;';
    } else if (cmd == 'PS1') {
      response = 'PS1;';
    }
    // Read meter
    else if (cmd.startsWith('RM')) {
      response = 'RM00000;';
    }
    // Antenna selector
    else if (cmd.startsWith('AN')) {
      response = 'AN0;';
    }
    // Function key
    else if (cmd.startsWith('FN')) {
      response = 'FN0;';
    }
    // VFO select
    else if (cmd.startsWith('FR') || cmd.startsWith('FT')) {
      response = '${cmd.substring(0, 2)}0;';
    } else {
      // Unknown command — respond with ? for error
      _log('CAT unknown command: $cmd');
      response = '?;';
    }

    _sendResponse(response);
  }

  /// Builds the TS-2000 IF response (transceiver information).
  String _buildIfResponse() {
    final sb = StringBuffer('IF');
    sb.write(_cachedFrequencyA.toString().padLeft(11, '0')); // P1: frequency
    sb.write('0000'); // P2: step
    sb.write('+00000'); // P3: RIT/XIT offset
    sb.write('0'); // P4: RIT on/off
    sb.write('0'); // P5: XIT on/off
    sb.write('0'); // P6: memory bank
    sb.write('00'); // P7: memory channel
    sb.write(_pttActive ? '1' : '0'); // P8: TX status
    sb.write('4'); // P9: operating mode (4=FM)
    sb.write('0'); // P10: function key
    sb.write('0'); // P11: scan
    sb.write('0'); // P12: split
    sb.write('0'); // P13: CTCSS tone
    sb.write('00'); // P14: tone number
    sb.write('0'); // P15: shift
    sb.write(';');
    return sb.toString();
  }

  void _sendResponse(String response) {
    if (!_running || _masterFd < 0) return;
    final bytes = Uint8List.fromList(ascii.encode(response));
    final buf = calloc<Uint8>(bytes.length);
    try {
      for (int i = 0; i < bytes.length; i++) {
        buf[i] = bytes[i];
      }
      _PtyNative.write(_masterFd, buf.cast<Void>(), bytes.length);
    } catch (e) {
      _log('CAT write error: $e');
    } finally {
      calloc.free(buf);
    }
  }

  void _setRadioFrequency(int freqHz, String vfo) {
    if (freqHz <= 0 || freqHz > 2147483647) return;

    int radioId = _activeRadioId;
    if (radioId < 0) radioId = _getFirstConnectedRadioId();
    if (radioId < 0) return;

    final info = _broker.getValueDynamic(radioId, 'Info');
    if (info == null) return;

    final channelCount =
        (info is Map ? info['channel_count'] as int? : null) ?? 0;
    if (channelCount <= 0) return;

    final scratchIndex = channelCount - 1;
    _broker.dispatch(
        radioId,
        'WriteChannel',
        {
          'channel_id': scratchIndex,
          'rx_freq': freqHz,
          'tx_freq': freqHz,
          'name_str': 'QF',
        },
        store: false);

    final eventName =
        vfo == 'B' ? 'ChannelChangeVfoB' : 'ChannelChangeVfoA';
    _broker.dispatch(radioId, eventName, scratchIndex, store: false);
    _log('CAT set VFO $vfo freq: $freqHz Hz → scratch channel $scratchIndex');
  }

  void _setPtt(bool on) {
    final wasActive = _pttActive;
    _pttActive = on;

    if (on && !wasActive) {
      _pttSilenceTimer?.cancel();
      _pttSilenceTimer =
          Timer.periodic(const Duration(milliseconds: 80), (_) {
        _dispatchSilence();
      });
      _pttTimeoutTimer?.cancel();
      _pttTimeoutTimer = Timer(
          const Duration(milliseconds: _pttTimeoutMs), _pttTimeoutCallback);
      _log('CAT PTT ON');
      _broker.dispatch(1, 'ExternalPttState', true, store: false);
    } else if (!on && wasActive) {
      _pttSilenceTimer?.cancel();
      _pttSilenceTimer = null;
      _pttTimeoutTimer?.cancel();
      _pttTimeoutTimer = null;
      _log('CAT PTT OFF');
      _broker.dispatch(1, 'ExternalPttState', false, store: false);
    }
  }

  void _pttTimeoutCallback() {
    if (_pttActive) {
      _log('CAT PTT auto-released after timeout');
      _setPtt(false);
    }
  }

  void _dispatchSilence() {
    if (!_pttActive) return;
    int radioId = _activeRadioId;
    if (radioId < 0) radioId = _getFirstConnectedRadioId();
    if (radioId < 0) return;

    // 100ms of 32kHz 16-bit mono silence = 6400 bytes
    final silence = List<int>.filled(6400, 0);
    _broker.dispatch(radioId, 'TransmitVoicePCM', silence, store: false);
  }

  int _getFirstConnectedRadioId() {
    final radios = _broker.getValueDynamic(1, 'ConnectedRadios');
    if (radios is List) {
      for (final item in radios) {
        if (item is Map) {
          final id = item['deviceId'] as int?;
          if (id != null && id > 0) return id;
        }
      }
    }
    return -1;
  }

  void _log(String message) {
    _broker.logInfo(message);
  }

  void dispose() {
    _stop();
    _broker.dispose();
  }
}
