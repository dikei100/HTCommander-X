import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../platform/bluetooth_service.dart';
import '../../radio/gaia_protocol.dart';
import 'native_methods.dart';

/// Linux Bluetooth transport using direct native RFCOMM sockets via dart:ffi.
///
/// Strategy: Use SDP to discover the SPP command channel, then connect with a
/// native RFCOMM socket and verify GAIA protocol response. Falls back to
/// probing channels 1-10 if SDP fails.
///
/// The blocking connection + read loop runs in a separate Dart Isolate so the
/// main isolate UI thread is never blocked.
class LinuxRadioBluetooth extends RadioBluetoothTransport {
  final String _macAddress;
  bool _connected = false;
  Isolate? _isolate;
  SendPort? _toIsolate;
  StreamSubscription<dynamic>? _fromIsolateSub;

  LinuxRadioBluetooth(this._macAddress);

  @override
  bool get isConnected => _connected;

  @override
  void connect() {
    if (_connected || _isolate != null) return;

    final receivePort = ReceivePort();
    _fromIsolateSub = receivePort.listen(_handleIsolateMessage);

    final mac = _macAddress.replaceAll(':', '').replaceAll('-', '').toUpperCase();

    Isolate.spawn(
      _isolateEntry,
      _IsolateStartArgs(receivePort.sendPort, mac),
    ).then((isolate) {
      _isolate = isolate;
    }).catchError((Object error) {
      _fromIsolateSub?.cancel();
      _fromIsolateSub = null;
      onDataReceived?.call(
        Exception('Failed to spawn isolate: $error'),
        null,
      );
    });
  }

  @override
  void disconnect() {
    _connected = false;
    _toIsolate?.send({'cmd': 'disconnect'});
    _cleanup();
  }

  @override
  void enqueueWrite(int expectedResponse, Uint8List cmdData) {
    if (!_connected || _toIsolate == null) return;
    final frame = GaiaProtocol.encode(cmdData);
    _toIsolate!.send({'cmd': 'write', 'data': frame});
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _toIsolate = message;
      return;
    }
    if (message is! Map<String, dynamic>) return;

    final event = message['event'] as String?;
    switch (event) {
      case 'connected':
        _connected = true;
        onConnected?.call();
      case 'data':
        final payload = message['payload'] as Uint8List;
        onDataReceived?.call(null, payload);
      case 'error':
        final msg = message['msg'] as String? ?? 'Unknown error';
        onDataReceived?.call(Exception(msg), null);
      case 'disconnected':
        _connected = false;
        _cleanup();
        onDataReceived?.call(
          Exception(message['msg'] as String? ?? 'Disconnected'),
          null,
        );
    }
  }

  void _cleanup() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
    _fromIsolateSub?.cancel();
    _fromIsolateSub = null;
  }

  // ---------------------------------------------------------------------------
  // Isolate entry point — all blocking I/O happens here
  // ---------------------------------------------------------------------------

  static Future<void> _isolateEntry(_IsolateStartArgs args) async {
    final toMain = args.mainPort;
    final receivePort = ReceivePort();
    toMain.send(receivePort.sendPort);

    final mac = args.mac;
    final macColon = _formatMacColon(mac);
    final bdaddr = parseMacAddress(mac);

    // State
    var running = true;
    var rfcommFd = -1;

    // Listen for commands from the main isolate
    receivePort.listen((dynamic message) {
      if (message is! Map<String, dynamic>) return;
      final cmd = message['cmd'] as String?;
      switch (cmd) {
        case 'write':
          if (rfcommFd < 0) return;
          final data = message['data'] as Uint8List;
          _writeAll(rfcommFd, data);
        case 'disconnect':
          running = false;
      }
    });

    // Connection with retries
    for (int attempt = 1; attempt <= 3 && running; attempt++) {
      try {
        // Step 1: ACL connect via bluetoothctl
        await _aclConnect(macColon);

        // Step 2: SDP discovery
        final sppChannels = await _discoverSppChannels(macColon);

        if (sppChannels != null && sppChannels.isNotEmpty) {
          rfcommFd = _connectToGaiaChannel(bdaddr, sppChannels);
        }

        // Step 3: Probe channels 1-10 if SDP failed
        if (rfcommFd < 0) {
          rfcommFd = _probeChannels(bdaddr);
        }

        if (rfcommFd >= 0) break;

        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        if (rfcommFd >= 0) {
          NativeMethods.close(rfcommFd);
          rfcommFd = -1;
        }
        if (attempt < 3 && running) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (rfcommFd < 0) {
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'Unable to connect — no GAIA-responsive channel found',
      });
      return;
    }

    // Set non-blocking mode
    final curFlags = NativeMethods.fcntl(rfcommFd, fGetfl);
    if (curFlags < 0) {
      NativeMethods.close(rfcommFd);
      toMain.send(<String, dynamic>{
        'event': 'disconnected',
        'msg': 'Failed to get socket flags',
      });
      return;
    }
    NativeMethods.fcntl3(rfcommFd, fSetfl, curFlags | oNonblock);

    // Notify main isolate that connection is established
    toMain.send(<String, dynamic>{'event': 'connected'});

    // Read loop
    _runReadLoop(rfcommFd, toMain, () => running);

    // Cleanup
    NativeMethods.close(rfcommFd);
    rfcommFd = -1;
    toMain.send(<String, dynamic>{
      'event': 'disconnected',
      'msg': 'Connection closed',
    });
  }

  static void _runReadLoop(
    int fd,
    SendPort toMain,
    bool Function() isRunning,
  ) {
    final accumulator = Uint8List(4096);
    var accPtr = 0;
    var accLen = 0;
    final readBufSize = 1024;
    final readBuf = calloc<Uint8>(readBufSize);

    try {
      while (isRunning()) {
        final bytesRead =
            NativeMethods.read(fd, readBuf.cast<Void>(), readBufSize);

        if (bytesRead < 0) {
          final err = NativeMethods.errno;
          if (err == eagain || err == eintr) {
            // No data available — sleep and retry
            sleep(const Duration(milliseconds: 50));
            continue;
          }
          // Real error
          break;
        }

        if (bytesRead == 0) {
          // Remote closed connection
          break;
        }

        // Copy native buffer into accumulator
        final space = accumulator.length - (accPtr + accLen);
        if (space <= 0) {
          accPtr = 0;
          accLen = 0;
        }

        // Ensure we don't overflow the accumulator
        final toCopy =
            bytesRead <= (accumulator.length - (accPtr + accLen))
                ? bytesRead
                : (accumulator.length - (accPtr + accLen));
        for (int i = 0; i < toCopy; i++) {
          accumulator[accPtr + accLen + i] = readBuf[i];
        }
        accLen += toCopy;

        if (accLen < 8) continue;

        // Decode GAIA frames
        while (true) {
          final (consumed, cmd) =
              GaiaProtocol.decode(accumulator, accPtr, accLen);
          if (consumed == 0) break;
          final skip = consumed < 0 ? accLen : consumed;
          accPtr += skip;
          accLen -= skip;
          if (cmd != null) {
            // Send decoded command to main isolate (Uint8List is transferable)
            toMain.send(<String, dynamic>{'event': 'data', 'payload': cmd});
          }
          if (consumed < 0) break;
        }

        if (accLen == 0) accPtr = 0;
        if (accPtr > 2048) {
          accumulator.setRange(0, accLen, accumulator, accPtr);
          accPtr = 0;
        }
      }
    } finally {
      calloc.free(readBuf);
    }
  }

  // --- Connection helpers (run in isolate) ---

  static Future<void> _aclConnect(String macColon) async {
    try {
      await Process.run('bluetoothctl', ['connect', macColon]);
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
      // ACL connect failure is non-fatal — direct RFCOMM may still work
    }
  }

  static Future<List<int>?> _discoverSppChannels(String macColon) async {
    try {
      final result = await Process.run('sdptool', ['browse', macColon]);
      if (result.exitCode != 0) return null;

      final output = result.stdout as String;
      if (output.isEmpty) return null;

      return _parseSdptoolOutput(output);
    } catch (_) {
      return null;
    }
  }

  static List<int> _parseSdptoolOutput(String output) {
    final sppChannels = <int>[];
    final allChannels = <int>[];
    final records = output.split('Service Name:');
    final channelRegex = RegExp(r'Channel:\s*(\d+)');

    for (final record in records) {
      final match = channelRegex.firstMatch(record);
      if (match == null) continue;

      final channel = int.tryParse(match.group(1)!);
      if (channel == null || channel < 1 || channel > 30) continue;

      final isSpp = record.contains('SPP Dev') ||
          record.contains('Serial Port') ||
          record.contains('00001101-0000-1000-8000-00805f9b34fb');

      if (isSpp) {
        sppChannels.add(channel);
      } else {
        allChannels.add(channel);
      }
    }

    return sppChannels.isNotEmpty ? sppChannels : allChannels;
  }

  static int _connectToGaiaChannel(List<int> bdaddr, List<int> channels) {
    for (final ch in channels) {
      final fd = _createRfcommFd(bdaddr, ch);
      if (fd < 0) continue;

      try {
        if (_verifyGaiaResponse(fd, ch)) return fd;
      } catch (_) {
        // Verification exception — close and try next
      }

      NativeMethods.close(fd);
    }
    return -1;
  }

  static int _probeChannels(List<int> bdaddr) {
    for (int ch = 1; ch <= 10; ch++) {
      final fd = _createRfcommFd(bdaddr, ch);
      if (fd < 0) continue;

      try {
        if (_verifyGaiaResponse(fd, ch)) return fd;
      } catch (_) {
        // Verification exception
      }

      NativeMethods.close(fd);
    }
    return -1;
  }

  /// Sends GAIA GET_DEV_ID and checks for a valid FF 01 response via poll().
  static bool _verifyGaiaResponse(int fd, int channel) {
    // Build GET_DEV_ID: group=BASIC(2), cmd=1
    final gaiaCmd =
        GaiaProtocol.encode(Uint8List.fromList([0x00, 0x02, 0x00, 0x01]));

    final writeBuf = calloc<Uint8>(gaiaCmd.length);
    try {
      for (int i = 0; i < gaiaCmd.length; i++) {
        writeBuf[i] = gaiaCmd[i];
      }
      final sent =
          NativeMethods.write(fd, writeBuf.cast<Void>(), gaiaCmd.length);
      if (sent < 0) return false;
    } finally {
      calloc.free(writeBuf);
    }

    // Poll for response with 3-second timeout
    final pfd = calloc<PollFd>();
    try {
      pfd.ref.fd = fd;
      pfd.ref.events = pollin;
      pfd.ref.revents = 0;

      final pollResult = NativeMethods.poll(pfd, 1, 3000);
      if (pollResult <= 0) return false;

      if ((pfd.ref.revents & (pollerr | pollhup | pollnval)) != 0) {
        return false;
      }

      if ((pfd.ref.revents & pollin) == 0) return false;
    } finally {
      calloc.free(pfd);
    }

    // Read response
    final readSize = 1024;
    final readBuf = calloc<Uint8>(readSize);
    try {
      final bytesRead =
          NativeMethods.read(fd, readBuf.cast<Void>(), readSize);
      if (bytesRead < 2) return false;

      // Verify GAIA header: FF 01
      return readBuf[0] == 0xFF && readBuf[1] == 0x01;
    } finally {
      calloc.free(readBuf);
    }
  }

  static int _createRfcommFd(List<int> bdaddr, int channel) {
    if (bdaddr.length < 6) return -1;

    final fd =
        NativeMethods.socket(afBluetooth, sockStream, btprotoRfcomm);
    if (fd < 0) return -1;

    final addr = buildSockaddrRc(bdaddr, channel);
    try {
      final result = NativeMethods.connect(fd, addr.cast<Void>(), 10);
      if (result < 0) {
        NativeMethods.close(fd);
        return -1;
      }
    } finally {
      calloc.free(addr);
    }

    return fd;
  }

  static void _writeAll(int fd, Uint8List data) {
    final buf = calloc<Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }

      var totalWritten = 0;
      while (totalWritten < data.length) {
        final written = NativeMethods.write(
          fd,
          (buf.cast<Uint8>() + totalWritten).cast<Void>(),
          data.length - totalWritten,
        );
        if (written > 0) {
          totalWritten += written;
        } else if (written < 0) {
          final err = NativeMethods.errno;
          if (err == eagain || err == eintr) {
            sleep(const Duration(milliseconds: 5));
            continue;
          }
          return; // Real write error
        } else {
          return; // written == 0, unexpected
        }
      }
    } finally {
      calloc.free(buf);
    }
  }

  static String _formatMacColon(String mac) {
    // mac is already clean uppercase hex, e.g. "AABBCCDDEEFF"
    final parts = <String>[];
    for (int i = 0; i < 6; i++) {
      parts.add(mac.substring(i * 2, i * 2 + 2));
    }
    return parts.join(':');
  }
}

/// Arguments passed to the isolate entry point.
class _IsolateStartArgs {
  final SendPort mainPort;
  final String mac;

  const _IsolateStartArgs(this.mainPort, this.mac);
}
