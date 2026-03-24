import 'dart:convert';
import 'dart:io';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';

/// A BBS station entry with traffic statistics.
class BbsStation {
  final String callSign;
  DateTime lastSeen;
  int packetsIn;
  int packetsOut;
  int bytesIn;
  int bytesOut;
  String state; // 'idle', 'connecting', 'connected', 'disconnecting'

  BbsStation({
    required this.callSign,
    DateTime? lastSeen,
    this.packetsIn = 0,
    this.packetsOut = 0,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.state = 'idle',
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'callSign': callSign,
        'lastSeen': lastSeen.toIso8601String(),
        'packetsIn': packetsIn,
        'packetsOut': packetsOut,
        'bytesIn': bytesIn,
        'bytesOut': bytesOut,
      };

  factory BbsStation.fromJson(Map<String, dynamic> json) => BbsStation(
        callSign: json['callSign'] as String? ?? '',
        lastSeen: DateTime.tryParse(json['lastSeen'] ?? ''),
        packetsIn: json['packetsIn'] as int? ?? 0,
        packetsOut: json['packetsOut'] as int? ?? 0,
        bytesIn: json['bytesIn'] as int? ?? 0,
        bytesOut: json['bytesOut'] as int? ?? 0,
      );
}

/// A BBS message.
class BbsMessage {
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime time;
  final bool isRead;

  const BbsMessage({
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.time,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'subject': subject,
        'body': body,
        'time': time.toIso8601String(),
        'isRead': isRead,
      };

  factory BbsMessage.fromJson(Map<String, dynamic> json) => BbsMessage(
        from: json['from'] as String? ?? '',
        to: json['to'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        body: json['body'] as String? ?? '',
        time: DateTime.tryParse(json['time'] ?? '') ?? DateTime.now(),
        isRead: json['isRead'] as bool? ?? false,
      );
}

/// Manages BBS station tracking, messaging, and AX.25 sessions.
///
/// Port of HTCommander.Core/BbsHandler.cs
class BbsHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  final List<BbsStation> _stations = [];
  final List<BbsMessage> _messages = [];
  String? _appDataPath;
  static const int _maxMessages = 500;
  static const String _messagesFileName = 'bbs_messages.json';

  List<BbsStation> get stations => List.unmodifiable(_stations);
  List<BbsMessage> get messages => List.unmodifiable(_messages);

  BbsHandler() {
    _broker.subscribe(1, 'CreateBbs', _onCreateBbs);
    _broker.subscribe(1, 'RemoveBbs', _onRemoveBbs);
    _broker.subscribe(1, 'GetBbsStatus', _onGetBbsStatus);
    _broker.subscribe(1, 'BbsConnect', _onBbsConnect);
    _broker.subscribe(1, 'BbsDisconnect', _onBbsDisconnect);
    _broker.subscribe(1, 'BbsSendMessage', _onBbsSendMessage);
    _broker.subscribe(1, 'RequestBbsMessages', _onRequestMessages);

    // Listen for incoming data frames for BBS protocol
    _broker.subscribe(
        DataBroker.allDevices, 'UniqueDataFrame', _onUniqueDataFrame);
  }

  /// Initialize persistence. Call after app data path is known.
  void initialize(String appDataPath) {
    _appDataPath = appDataPath;
    _loadMessages();
  }

  void _onCreateBbs(int deviceId, String name, Object? data) {
    if (data is! String) return;
    for (final station in _stations) {
      if (station.callSign == data) return;
    }
    final station = BbsStation(callSign: data);
    _stations.add(station);
    _broker.dispatch(1, 'BbsCreated', station, store: false);
    _dispatchList();
  }

  void _onRemoveBbs(int deviceId, String name, Object? data) {
    if (data is! String) return;
    _stations.removeWhere((s) => s.callSign == data);
    _dispatchList();
  }

  void _onGetBbsStatus(int deviceId, String name, Object? data) {
    _dispatchList();
  }

  void _onBbsConnect(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final callsign = data['callsign'] as String?;
    final radioDeviceId = data['radioDeviceId'] as int?;
    if (callsign == null || radioDeviceId == null) return;

    final station = _stations.firstWhere(
      (s) => s.callSign == callsign,
      orElse: () {
        final s = BbsStation(callSign: callsign, state: 'connecting');
        _stations.add(s);
        return s;
      },
    );
    station.state = 'connecting';
    _dispatchList();

    _broker.logInfo('[BBS] Connecting to $callsign on radio $radioDeviceId');

    // Lock the radio channel for exclusive BBS use
    _broker.dispatch(radioDeviceId, 'LockChannel', {
      'usage': 'BBS',
      'callsign': callsign,
    }, store: false);

    // TODO: Initiate AX.25 SABM connection when ax25_link.dart is available
    // For now, mark as connected after a brief delay
    Future.delayed(const Duration(seconds: 1), () {
      station.state = 'connected';
      _dispatchList();
    });
  }

  void _onBbsDisconnect(int deviceId, String name, Object? data) {
    if (data is! String) return;
    for (final station in _stations) {
      if (station.callSign == data) {
        station.state = 'idle';
      }
    }
    _dispatchList();
  }

  void _onBbsSendMessage(int deviceId, String name, Object? data) {
    if (data is! BbsMessage) return;
    _messages.add(data);
    while (_messages.length > _maxMessages) {
      _messages.removeAt(0);
    }
    _saveMessages();
    _broker.dispatch(1, 'BbsMessagesUpdated', _messages.length, store: false);
    _broker.logInfo('[BBS] Message queued to ${data.to}: ${data.subject}');
  }

  void _onRequestMessages(int deviceId, String name, Object? data) {
    _broker.dispatch(1, 'BbsMessages', List<BbsMessage>.from(_messages),
        store: false);
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    // TODO: Process incoming BBS protocol frames when AX.25 session layer is available
  }

  void _dispatchList() {
    _broker.dispatch(1, 'BbsList', List<BbsStation>.from(_stations),
        store: false);
  }

  void _loadMessages() {
    final path = _appDataPath;
    if (path == null) return;
    final file = File('$path/$_messagesFileName');
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is List) {
        for (final item in json) {
          if (item is Map<String, dynamic>) {
            _messages.add(BbsMessage.fromJson(item));
          }
        }
      }
    } catch (_) {}
  }

  void _saveMessages() {
    final path = _appDataPath;
    if (path == null) return;
    try {
      File('$path/$_messagesFileName')
          .writeAsStringSync(jsonEncode(_messages.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  void dispose() {
    _saveMessages();
    _broker.dispose();
  }
}
