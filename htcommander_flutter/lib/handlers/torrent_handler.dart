import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/binary_utils.dart';

/// A torrent file transfer entry.
class TorrentFile {
  final String id;
  final String fileName;
  final int fileSize;
  String mode; // 'idle', 'seeding', 'downloading', 'paused'
  final int totalBlocks;
  int receivedBlocks;
  final int blockSize;
  Uint8List? fileData;
  String? md5Hash;
  DateTime addedTime;

  TorrentFile({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mode,
    required this.totalBlocks,
    this.receivedBlocks = 0,
    this.blockSize = defaultBlockSize,
    this.fileData,
    this.md5Hash,
    DateTime? addedTime,
  }) : addedTime = addedTime ?? DateTime.now();

  static const int defaultBlockSize = 170;

  double get progress =>
      totalBlocks > 0 ? receivedBlocks / totalBlocks : 0.0;

  bool get isComplete => receivedBlocks >= totalBlocks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'fileSize': fileSize,
        'mode': mode,
        'totalBlocks': totalBlocks,
        'receivedBlocks': receivedBlocks,
        'blockSize': blockSize,
        'md5Hash': md5Hash,
        'addedTime': addedTime.toIso8601String(),
      };

  factory TorrentFile.fromJson(Map<String, dynamic> json) => TorrentFile(
        id: json['id'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        fileSize: json['fileSize'] as int? ?? 0,
        mode: json['mode'] as String? ?? 'idle',
        totalBlocks: json['totalBlocks'] as int? ?? 0,
        receivedBlocks: json['receivedBlocks'] as int? ?? 0,
        blockSize: json['blockSize'] as int? ?? defaultBlockSize,
        md5Hash: json['md5Hash'] as String?,
        addedTime: DateTime.tryParse(json['addedTime'] ?? ''),
      );

  /// Creates a TorrentFile from a local file path.
  static TorrentFile? fromFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final bytes = file.readAsBytesSync();
    final totalBlocks = (bytes.length + defaultBlockSize - 1) ~/ defaultBlockSize;

    return TorrentFile(
      id: BinaryUtils.bytesToHex(
          Uint8List.fromList(filePath.codeUnits.take(16).toList())),
      fileName: filePath.split('/').last,
      fileSize: bytes.length,
      mode: 'seeding',
      totalBlocks: totalBlocks,
      receivedBlocks: totalBlocks,
      fileData: bytes,
    );
  }
}

/// A discovered torrent station (peer).
class TorrentStation {
  final String callSign;
  final String fileName;
  final int fileSize;
  final String id;
  DateTime lastSeen;

  TorrentStation({
    required this.callSign,
    required this.fileName,
    required this.fileSize,
    required this.id,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

/// Manages torrent file transfers over radio.
///
/// Port of HTCommander.Core/Torrent.cs
class TorrentHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  final List<TorrentFile> _files = [];
  final List<TorrentStation> _stations = [];
  String? _appDataPath;
  static const String _stateFileName = 'torrent_state.json';

  List<TorrentFile> get files => List.unmodifiable(_files);
  List<TorrentStation> get discoveredStations => List.unmodifiable(_stations);

  TorrentHandler() {
    _broker.subscribe(0, 'TorrentAddFile', _onAddFile);
    _broker.subscribe(0, 'TorrentRemoveFile', _onRemoveFile);
    _broker.subscribe(0, 'TorrentSetFileMode', _onSetFileMode);
    _broker.subscribe(0, 'TorrentGetFiles', _onGetFiles);
    _broker.subscribe(0, 'TorrentGetStations', _onGetStations);

    // Listen for incoming data frames for torrent protocol
    _broker.subscribe(
        DataBroker.allDevices, 'UniqueDataFrame', _onUniqueDataFrame);
  }

  /// Initialize persistence. Call after app data path is known.
  void initialize(String appDataPath) {
    _appDataPath = appDataPath;
    _loadState();
    _dispatchFiles();
    _dispatchStations();
  }

  void _onAddFile(int deviceId, String name, Object? data) {
    if (data is TorrentFile) {
      // Check for duplicate
      if (_files.any((f) => f.id == data.id)) return;
      _files.add(data);
      _saveState();
      _dispatchFiles();
      _broker.logInfo('[Torrent] Added file: ${data.fileName}');
    } else if (data is String) {
      // Treat as file path
      final file = TorrentFile.fromFile(data);
      if (file != null) {
        _files.add(file);
        _saveState();
        _dispatchFiles();
        _broker.logInfo('[Torrent] Added file from path: ${file.fileName}');
      }
    }
  }

  void _onRemoveFile(int deviceId, String name, Object? data) {
    if (data is String) {
      _files.removeWhere((f) => f.id == data);
      _saveState();
      _dispatchFiles();
    }
  }

  void _onSetFileMode(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final id = data['id'] as String?;
    final mode = data['mode'] as String?;
    if (id == null || mode == null) return;

    for (final file in _files) {
      if (file.id == id) {
        file.mode = mode;
        break;
      }
    }
    _saveState();
    _dispatchFiles();
  }

  void _onGetFiles(int deviceId, String name, Object? data) {
    _dispatchFiles();
  }

  void _onGetStations(int deviceId, String name, Object? data) {
    _dispatchStations();
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    // TODO: Process torrent protocol frames (discovery, block requests, block data)
    // when the full packet protocol is available from Phase 5
  }

  void _dispatchFiles() {
    _broker.dispatch(1, 'TorrentFiles', List<TorrentFile>.from(_files),
        store: false);
  }

  void _dispatchStations() {
    _broker.dispatch(1, 'TorrentStations',
        List<TorrentStation>.from(_stations), store: false);
  }

  void _loadState() {
    final path = _appDataPath;
    if (path == null) return;
    final file = File('$path/$_stateFileName');
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map) {
        final files = json['files'];
        if (files is List) {
          for (final item in files) {
            if (item is Map<String, dynamic>) {
              _files.add(TorrentFile.fromJson(item));
            }
          }
        }
      }
    } catch (_) {}
  }

  void _saveState() {
    final path = _appDataPath;
    if (path == null) return;
    try {
      final json = {
        'files': _files.map((f) => f.toJson()).toList(),
      };
      File('$path/$_stateFileName').writeAsStringSync(jsonEncode(json));
    } catch (_) {}
  }

  void dispose() {
    _saveState();
    _broker.dispose();
  }
}
