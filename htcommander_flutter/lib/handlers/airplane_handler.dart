import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/data_broker.dart';
import '../core/data_broker_client.dart';

/// Represents a single aircraft as reported by Dump1090.
///
/// Port of HTCommander.Core/Airplanes/Aircraft.cs
class Aircraft {
  String? hex;
  String? flight;
  double? latitude;
  double? longitude;
  Object? altitude;
  int? altitudeGeometric;
  Object? altitudeBaro;
  double? speed;
  double? groundSpeed;
  double? track;
  String? squawk;
  int? verticalRate;
  int? baroRate;
  int? messages;
  double? seen;
  double? seenPos;
  double? rssi;
  String? category;
  int? nic;
  int? nacP;
  int? nacV;
  int? sil;
  String? emergency;

  Aircraft();

  /// Parses an [Aircraft] from a JSON map.
  factory Aircraft.fromJson(Map<String, dynamic> json) {
    final a = Aircraft();
    a.hex = json['hex'] as String?;
    a.flight = (json['flight'] as String?)?.trim();
    a.latitude = (json['lat'] as num?)?.toDouble();
    a.longitude = (json['lon'] as num?)?.toDouble();
    a.altitude = json['altitude'];
    a.altitudeGeometric = json['alt_geom'] as int?;
    a.altitudeBaro = json['alt_baro'];
    a.speed = (json['speed'] as num?)?.toDouble();
    a.groundSpeed = (json['gs'] as num?)?.toDouble();
    a.track = (json['track'] as num?)?.toDouble();
    a.squawk = json['squawk'] as String?;
    a.verticalRate = json['vert_rate'] as int?;
    a.baroRate = json['baro_rate'] as int?;
    a.messages = json['messages'] as int?;
    a.seen = (json['seen'] as num?)?.toDouble();
    a.seenPos = (json['seen_pos'] as num?)?.toDouble();
    a.rssi = (json['rssi'] as num?)?.toDouble();
    a.category = json['category'] as String?;
    a.nic = json['nic'] as int?;
    a.nacP = json['nac_p'] as int?;
    a.nacV = json['nac_v'] as int?;
    a.sil = json['sil'] as int?;
    a.emergency = json['emergency'] as String?;
    return a;
  }

  /// Returns the best available altitude display string.
  String getAltitudeDisplay() {
    if (altitudeBaro != null) return altitudeBaro.toString();
    if (altitude != null) return altitude.toString();
    if (altitudeGeometric != null) return altitudeGeometric.toString();
    return '\u2014'; // em dash
  }

  /// Returns the best available speed value.
  double? getSpeed() => groundSpeed ?? speed;

  /// Returns the best available vertical rate.
  int? getVerticalRate() => baroRate ?? verticalRate;
}

/// Root JSON object returned by Dump1090's aircraft.json endpoint.
///
/// Port of HTCommander.Core/Airplanes/AircraftResponse.cs
class AircraftResponse {
  double now = 0;
  int messages = 0;
  List<Aircraft> aircraft = [];

  AircraftResponse();

  factory AircraftResponse.fromJson(Map<String, dynamic> json) {
    final r = AircraftResponse();
    r.now = (json['now'] as num?)?.toDouble() ?? 0;
    r.messages = (json['messages'] as num?)?.toInt() ?? 0;
    final list = json['aircraft'] as List<dynamic>?;
    if (list != null) {
      r.aircraft = list
          .whereType<Map<String, dynamic>>()
          .map(Aircraft.fromJson)
          .toList();
    }
    return r;
  }
}

/// HTTP client that polls a Dump1090 aircraft.json endpoint.
///
/// Port of HTCommander.Core/Airplanes/Dump1090HttpClient.cs
class Dump1090HttpClient {
  final HttpClient _http = HttpClient();
  final Uri _uri;

  Dump1090HttpClient(String url) : _uri = Uri.parse(url) {
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  /// Fetches the current aircraft list from the Dump1090 endpoint.
  Future<AircraftResponse> getAircraft() async {
    final request = await _http.getUrl(_uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException(
          'HTTP ${response.statusCode}', uri: _uri);
    }
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return AircraftResponse.fromJson(json);
  }

  /// Continuously polls the endpoint. Waits one second between requests.
  Future<void> poll(
    void Function(AircraftResponse response) onData, {
    required bool Function() isCancelled,
  }) async {
    while (!isCancelled()) {
      try {
        final data = await getAircraft();
        onData(data);
      } catch (_) {
        // Swallow errors; keep polling
      }
      // Wait 1 second before next poll
      await Future<void>.delayed(const Duration(seconds: 1));
      if (isCancelled()) break;
    }
  }

  void close() {
    _http.close(force: true);
  }
}

/// Data Broker handler that polls a Dump1090 endpoint for airplane data.
/// Reads the "AirplaneServer" setting from device 0 and, when present,
/// uses [Dump1090HttpClient] to periodically fetch aircraft.
/// Each successful poll dispatches an "Airplanes" event with the aircraft list.
///
/// Port of HTCommander.Core/Airplanes/AirplaneHandler.cs
class AirplaneHandler {
  final DataBrokerClient _broker = DataBrokerClient();
  Dump1090HttpClient? _client;
  bool _cancelled = false;
  String? _currentUrl;
  bool _showOnMap = false;
  bool _disposed = false;

  AirplaneHandler() {
    // Subscribe to AirplaneServer setting changes on device 0
    _broker.subscribe(0, 'AirplaneServer', _onAirplaneServerChanged);

    // Subscribe to ShowAirplanesOnMap to start/stop polling
    _broker.subscribe(0, 'ShowAirplanesOnMap', _onShowAirplanesOnMapChanged);

    // Subscribe to test requests on device 1
    _broker.subscribe(1, 'TestAirplaneServer', _onTestAirplaneServer);

    // Load initial state
    _showOnMap = DataBroker.getValue<int>(0, 'ShowAirplanesOnMap', 0) == 1;
    final server = DataBroker.getValue<String>(0, 'AirplaneServer', '');
    if (server.isNotEmpty) {
      _applyServerSetting(server);
    }
  }

  void _onAirplaneServerChanged(int deviceId, String name, Object? data) {
    final server = data is String ? data : '';
    _applyServerSetting(server);
  }

  void _onShowAirplanesOnMapChanged(int deviceId, String name, Object? data) {
    _showOnMap = data is int && data == 1;
    final server = DataBroker.getValue<String>(0, 'AirplaneServer', '');
    _applyServerSetting(server);
  }

  /// Applies a new server setting: stops any existing poll loop and, if
  /// the value is non-empty and ShowAirplanesOnMap is true, starts a new one.
  void _applyServerSetting(String server) {
    final url = _showOnMap ? _resolveUrl(server) : null;

    // If the resolved URL hasn't changed, nothing to do
    if (url == _currentUrl) return;

    _stopPolling();
    _currentUrl = url;

    if (url != null && url.isNotEmpty) {
      _startPolling(url);
    }
  }

  /// Resolves the server setting to a full URL.
  static String? _resolveUrl(String server) {
    server = server.trim();
    if (server.isEmpty) return null;

    if (server.startsWith('http://') || server.startsWith('https://')) {
      return server;
    }

    return 'http://$server/data/aircraft.json';
  }

  void _startPolling(String url) {
    _cancelled = false;
    _client = Dump1090HttpClient(url);
    final client = _client!;

    // Fire and forget the poll loop
    client.poll(
      (response) {
        _broker.dispatch(0, 'Airplanes', response.aircraft, store: false);
      },
      isCancelled: () => _cancelled,
    );
  }

  void _stopPolling() {
    _cancelled = true;
    _client?.close();
    _client = null;
  }

  /// Handles a test request from settings. Tries a single fetch against the
  /// provided server value and dispatches the result on device 1.
  Future<void> _onTestAirplaneServer(
      int deviceId, String name, Object? data) async {
    final server = data is String ? data : '';
    final url = _resolveUrl(server);
    if (url == null || url.isEmpty) {
      _broker.dispatch(
          1, 'TestAirplaneServerResult', 'Failed: empty server address',
          store: false);
      return;
    }

    try {
      final client = Dump1090HttpClient(url);
      try {
        final response = await client.getAircraft();
        final count = response.aircraft.length;
        _broker.dispatch(1, 'TestAirplaneServerResult',
            'Success, $count aircraft found.',
            store: false);
      } finally {
        client.close();
      }
    } catch (e) {
      _broker.dispatch(
          1, 'TestAirplaneServerResult', 'Failed: $e', store: false);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopPolling();
    _broker.dispose();
  }
}
