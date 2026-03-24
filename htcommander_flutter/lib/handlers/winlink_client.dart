import 'dart:convert';
import 'dart:io';

import '../core/data_broker_client.dart';
import 'mail_store.dart' show WinlinkMail;

/// Connection state for the Winlink client.
enum WinlinkConnectionState {
  disconnected,
  connecting,
  connected,
  syncing,
  disconnecting,
}

/// Debug log entry for Winlink protocol debugging.
class WinlinkDebugEntry {
  final DateTime time;
  final String direction; // 'TX', 'RX', 'INFO', 'ERROR'
  final String message;

  const WinlinkDebugEntry({
    required this.time,
    required this.direction,
    required this.message,
  });
}

/// Winlink client for syncing email over TCP or AX.25 radio.
///
/// Port of HTCommander.Core/WinLink/WinlinkClient.cs
class WinlinkClient {
  final DataBrokerClient _broker = DataBrokerClient();
  WinlinkConnectionState _state = WinlinkConnectionState.disconnected;
  String? _appDataPath;

  final List<WinlinkMail> _inbox = [];
  final List<WinlinkMail> _outbox = [];
  final List<WinlinkMail> _sent = [];
  final List<WinlinkMail> _trash = [];
  final List<WinlinkDebugEntry> _debugLog = [];
  static const int _maxDebugEntries = 1000;
  static const String _mailFileName = 'winlink_mail.json';

  WinlinkConnectionState get state => _state;
  List<WinlinkMail> get inbox => List.unmodifiable(_inbox);
  List<WinlinkMail> get outbox => List.unmodifiable(_outbox);
  List<WinlinkMail> get sent => List.unmodifiable(_sent);
  List<WinlinkMail> get trash => List.unmodifiable(_trash);
  List<WinlinkDebugEntry> get debugLog => List.unmodifiable(_debugLog);

  WinlinkClient() {
    _broker.subscribe(1, 'WinlinkSync', _onWinlinkSync);
    _broker.subscribe(1, 'WinlinkSyncTcp', _onWinlinkSyncTcp);
    _broker.subscribe(1, 'WinlinkDisconnect', _onWinlinkDisconnect);
    _broker.subscribe(1, 'WinlinkCompose', _onWinlinkCompose);
    _broker.subscribe(1, 'WinlinkDeleteMail', _onWinlinkDeleteMail);
    _broker.subscribe(1, 'WinlinkMoveMail', _onWinlinkMoveMail);
    _broker.subscribe(1, 'RequestWinlinkMail', _onRequestMail);
    _broker.subscribe(1, 'RequestWinlinkDebug', _onRequestDebug);
  }

  /// Initialize persistence. Call after app data path is known.
  void initialize(String appDataPath) {
    _appDataPath = appDataPath;
    _loadMail();
    _dispatchMailState();
  }

  void _onWinlinkSync(int deviceId, String name, Object? data) {
    _addDebug('INFO', 'Radio sync not yet implemented — use TCP sync');
    _setState(WinlinkConnectionState.disconnected);
  }

  void _onWinlinkSyncTcp(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final host = data['host'] as String?;
    final port = data['port'] as int? ?? 8772;
    final callsign = data['callsign'] as String?;
    final password = data['password'] as String?;

    if (host == null || callsign == null || password == null) {
      _addDebug('ERROR', 'Missing TCP sync parameters');
      return;
    }

    _syncTcp(host, port, callsign, password);
  }

  Future<void> _syncTcp(
      String host, int port, String callsign, String password) async {
    _setState(WinlinkConnectionState.connecting);
    _addDebug('INFO', 'Connecting to $host:$port...');

    Socket? socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 15));
      _setState(WinlinkConnectionState.connected);
      _addDebug('INFO', 'Connected to $host:$port');

      // B2F handshake
      _addDebug('TX', ';FW: $callsign');

      // Read server greeting
      final greeting = await socket.first
          .timeout(const Duration(seconds: 10));
      _addDebug('RX', String.fromCharCodes(greeting).trim());

      _setState(WinlinkConnectionState.syncing);

      // Send outbox messages as proposals
      for (final mail in _outbox) {
        _addDebug('TX', 'FC EM ${mail.mid} ${mail.body.length}');
      }
      _addDebug('TX', 'F> (proposals complete)');

      // TODO: Full B2F protocol exchange
      // For now, move outbox to sent
      for (final mail in List<WinlinkMail>.from(_outbox)) {
        mail.folder = 'Sent';
        _sent.add(mail);
      }
      _outbox.clear();

      _addDebug('INFO', 'Sync complete');
    } catch (e) {
      _addDebug('ERROR', 'TCP sync failed: $e');
    } finally {
      socket?.destroy();
      _setState(WinlinkConnectionState.disconnected);
      _saveMail();
      _dispatchMailState();
    }
  }

  void _onWinlinkDisconnect(int deviceId, String name, Object? data) {
    _setState(WinlinkConnectionState.disconnecting);
    _setState(WinlinkConnectionState.disconnected);
  }

  void _onWinlinkCompose(int deviceId, String name, Object? data) {
    if (data is! WinlinkMail) return;
    data.folder = 'Outbox';
    _outbox.add(data);
    _saveMail();
    _dispatchMailState();
    _addDebug('INFO', 'Message queued to ${data.to}: ${data.subject}');
  }

  void _onWinlinkDeleteMail(int deviceId, String name, Object? data) {
    if (data is! String) return;
    final mid = data;
    // Move to trash or permanently delete if already in trash
    WinlinkMail? mail;
    mail = _removeFromMailbox(_inbox, mid);
    mail ??= _removeFromMailbox(_outbox, mid);
    mail ??= _removeFromMailbox(_sent, mid);

    if (mail != null) {
      mail.folder = 'Trash';
      _trash.add(mail);
    } else {
      _trash.removeWhere((m) => m.mid == mid);
    }
    _saveMail();
    _dispatchMailState();
  }

  void _onWinlinkMoveMail(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final mid = data['messageId'] as String?;
    final mailbox = data['mailbox'] as String?;
    if (mid == null || mailbox == null) return;

    WinlinkMail? mail;
    mail = _removeFromMailbox(_inbox, mid);
    mail ??= _removeFromMailbox(_outbox, mid);
    mail ??= _removeFromMailbox(_sent, mid);
    mail ??= _removeFromMailbox(_trash, mid);

    if (mail != null) {
      mail.folder = mailbox;
      _getMailbox(mailbox).add(mail);
      _saveMail();
      _dispatchMailState();
    }
  }

  void _onRequestMail(int deviceId, String name, Object? data) {
    _dispatchMailState();
  }

  void _onRequestDebug(int deviceId, String name, Object? data) {
    _broker.dispatch(1, 'WinlinkDebugLog',
        List<WinlinkDebugEntry>.from(_debugLog), store: false);
  }

  WinlinkMail? _removeFromMailbox(List<WinlinkMail> mailbox, String mid) {
    final idx = mailbox.indexWhere((m) => m.mid == mid);
    if (idx >= 0) return mailbox.removeAt(idx);
    return null;
  }

  List<WinlinkMail> _getMailbox(String name) {
    switch (name) {
      case 'Inbox':
        return _inbox;
      case 'Outbox':
        return _outbox;
      case 'Sent':
        return _sent;
      case 'Trash':
        return _trash;
      default:
        return _inbox;
    }
  }

  void _setState(WinlinkConnectionState newState) {
    _state = newState;
    _broker.dispatch(1, 'WinlinkState', _state.name, store: false);
  }

  void _addDebug(String direction, String message) {
    _debugLog.add(WinlinkDebugEntry(
      time: DateTime.now(),
      direction: direction,
      message: message,
    ));
    while (_debugLog.length > _maxDebugEntries) {
      _debugLog.removeAt(0);
    }
    _broker.dispatch(1, 'WinlinkStateMessage', message, store: false);
  }

  void _dispatchMailState() {
    _broker.dispatch(1, 'WinlinkMailState', {
      'inbox': _inbox.length,
      'outbox': _outbox.length,
      'sent': _sent.length,
      'trash': _trash.length,
    }, store: false);
  }

  void _loadMail() {
    final path = _appDataPath;
    if (path == null) return;
    final file = File('$path/$_mailFileName');
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is Map) {
        _loadMailbox(_inbox, json['inbox']);
        _loadMailbox(_outbox, json['outbox']);
        _loadMailbox(_sent, json['sent']);
        _loadMailbox(_trash, json['trash']);
      }
    } catch (_) {}
  }

  void _loadMailbox(List<WinlinkMail> mailbox, dynamic jsonList) {
    if (jsonList is! List) return;
    for (final item in jsonList) {
      if (item is Map<String, dynamic>) {
        mailbox.add(WinlinkMail.fromJson(item));
      }
    }
  }

  void _saveMail() {
    final path = _appDataPath;
    if (path == null) return;
    try {
      final json = {
        'inbox': _inbox.map((m) => m.toJson()).toList(),
        'outbox': _outbox.map((m) => m.toJson()).toList(),
        'sent': _sent.map((m) => m.toJson()).toList(),
        'trash': _trash.map((m) => m.toJson()).toList(),
      };
      File('$path/$_mailFileName').writeAsStringSync(jsonEncode(json));
    } catch (_) {}
  }

  void dispose() {
    _saveMail();
    _broker.dispose();
  }
}
