import 'dart:io';
import 'dart:typed_data';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/ax25/ax25_packet.dart';
import '../radio/binary_utils.dart';
import '../radio/models/tnc_data_fragment.dart';

/// Stores received AX.25 packets in memory and persists them to a file.
///
/// Listens for UniqueDataFrame events and saves packets to "packets.ptcap".
/// Maintains the last [_maxPackets] packets in memory.
///
/// Port of HTCommander.Core/PacketStore.cs
class PacketStore {
  final DataBrokerClient _broker = DataBrokerClient();
  final List<AX25Packet> _packets = [];
  static const int _maxPackets = 2000;
  static const String _packetFileName = 'packets.ptcap';

  String? _appDataPath;
  IOSink? _packetFile;

  List<AX25Packet> get packets => List.unmodifiable(_packets);
  int get count => _packets.length;

  PacketStore() {
    _broker.subscribe(
        DataBroker.allDevices, 'UniqueDataFrame', _onUniqueDataFrame);
    _broker.subscribe(1, 'RequestPacketList', _onRequestPacketList);
  }

  /// Initializes persistence. Call after app data path is known.
  void initialize(String appDataPath) {
    _appDataPath = appDataPath;
    final dir = Directory(appDataPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _loadPackets();
    _openPacketFile();
    _broker.dispatch(1, 'PacketStoreReady', true, store: true);
  }

  void _openPacketFile() {
    final path = _appDataPath;
    if (path == null) return;
    try {
      final file = File('$path/$_packetFileName');
      _packetFile = file.openWrite(mode: FileMode.append);
    } catch (_) {
      // Persistence is best-effort
    }
  }

  void _loadPackets() {
    final path = _appDataPath;
    if (path == null) return;

    final file = File('$path/$_packetFileName');
    if (!file.existsSync()) return;

    List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } catch (_) {
      return;
    }

    // Load only the last _maxPackets lines
    final startIndex =
        lines.length > _maxPackets ? lines.length - _maxPackets : 0;

    for (var i = startIndex; i < lines.length; i++) {
      try {
        final packet = parsePacketLine(lines[i]);
        if (packet != null) {
          _packets.add(packet);
        }
      } catch (_) {
        // Skip malformed lines
      }
    }
  }

  /// Parses a CSV line from the packet file into an AX25Packet.
  /// Format: ticks,incoming,TncFrag4,channelId,regionId,channelName,hexData,encoding,frameType,corrections,radioMac
  static AX25Packet? parsePacketLine(String line) {
    final s = line.split(',');
    if (s.length < 5) return null;

    final ticks = int.tryParse(s[0]);
    if (ticks == null) return null;
    // C# ticks are 100ns intervals from 0001-01-01; Dart uses microseconds from epoch.
    final microseconds = (ticks - 621355968000000000) ~/ 10;
    final time = DateTime.fromMicrosecondsSinceEpoch(microseconds);
    final incoming = s[1] == '1';

    final type = s[2];
    if (type != 'TncFrag' &&
        type != 'TncFrag2' &&
        type != 'TncFrag3' &&
        type != 'TncFrag4') {
      return null;
    }

    final cid = int.tryParse(s[3]) ?? 0;
    var cn = (cid + 1).toString();
    Uint8List rawData;

    if (type == 'TncFrag') {
      if (s.length < 5) return null;
      rawData = BinaryUtils.hexToBytes(s[4]);
    } else if (type == 'TncFrag2') {
      if (s.length < 7) return null;
      cn = s[5];
      rawData = BinaryUtils.hexToBytes(s[6]);
    } else if (type == 'TncFrag3' || type == 'TncFrag4') {
      if (s.length < 10) return null;
      cn = s[5];
      rawData = BinaryUtils.hexToBytes(s[6]);
    } else {
      return null;
    }

    // Try to decode as AX.25 packet via TncDataFragment
    try {
      final fragment = TncDataFragment(
        finalFragment: true,
        fragmentId: 0,
        data: rawData,
        channelId: cid,
        regionId: 0,
      );
      fragment.time = time;
      fragment.incoming = incoming;
      fragment.channelName = cn;

      final packet = AX25Packet.decodeAx25Packet(fragment);
      if (packet != null) {
        return packet;
      }
    } catch (_) {
      // Fall through to create a minimal packet
    }

    // If AX.25 decode fails, create a minimal packet with raw data
    final packet = AX25Packet(
      addresses: [],
      data: rawData,
      time: time,
    );
    packet.incoming = incoming;
    packet.channelId = cid;
    packet.channelName = cn;
    return packet;
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (data is! AX25Packet) return;
    final packet = data;

    _writePacketToFile(packet);

    _packets.add(packet);
    while (_packets.length > _maxPackets) {
      _packets.removeAt(0);
    }

    _broker.dispatch(1, 'PacketStored', packet, store: false);
    _broker.dispatch(1, 'PacketStoreUpdated', _packets.length, store: false);
  }

  void _onRequestPacketList(int deviceId, String name, Object? data) {
    _broker.dispatch(1, 'PacketList', List<AX25Packet>.from(_packets),
        store: false);
  }

  void _writePacketToFile(AX25Packet packet) {
    final sink = _packetFile;
    if (sink == null) return;

    try {
      // Encode the packet frame for storage
      final frameBytes = packet.toByteArray();
      if (frameBytes == null || frameBytes.isEmpty) return;
      final hex = BinaryUtils.bytesToHex(frameBytes);

      // Convert DateTime to C#-compatible ticks for file compatibility
      final ticks =
          packet.time.microsecondsSinceEpoch * 10 + 621355968000000000;
      final line = '$ticks,${packet.incoming ? "1" : "0"},'
          'TncFrag4,${packet.channelId},0,'
          '${packet.channelName},$hex,'
          '0,0,-1,';
      sink.writeln(line);
    } catch (_) {
      // Best-effort persistence
    }
  }

  /// Formats a packet's data as a hex dump string (16 bytes per row).
  static String hexDump(Uint8List data) {
    final sb = StringBuffer();
    for (var i = 0; i < data.length; i += 16) {
      // Offset
      sb.write(i.toRadixString(16).padLeft(4, '0'));
      sb.write('  ');

      // Hex bytes
      for (var j = 0; j < 16; j++) {
        if (i + j < data.length) {
          sb.write(data[i + j].toRadixString(16).padLeft(2, '0'));
          sb.write(' ');
        } else {
          sb.write('   ');
        }
        if (j == 7) sb.write(' ');
      }

      sb.write(' ');

      // ASCII
      for (var j = 0; j < 16 && i + j < data.length; j++) {
        final b = data[i + j];
        sb.write(b >= 0x20 && b < 0x7F ? String.fromCharCode(b) : '.');
      }

      sb.writeln();
    }
    return sb.toString();
  }

  void clear() {
    _packets.clear();
    _broker.dispatch(1, 'PacketStoreUpdated', 0, store: false);
  }

  void dispose() {
    _packetFile?.close();
    _packetFile = null;
    _broker.dispose();
  }
}
