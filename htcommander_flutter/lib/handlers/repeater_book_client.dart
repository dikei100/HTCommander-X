import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../radio/models/radio_channel_info.dart';
import '../radio/radio_enums.dart';

/// A single repeater entry from RepeaterBook.
class RepeaterBookEntry {
  String callsign;
  double frequency;
  double inputFreq;
  double latitude;
  double longitude;
  String nearestCity;
  String state;
  String pl;
  String offset;
  String duplex;
  String use;
  String status;
  String county;
  String landmark;
  String mode;
  double distanceKm;

  RepeaterBookEntry({
    this.callsign = '',
    this.frequency = 0,
    this.inputFreq = 0,
    this.latitude = 0,
    this.longitude = 0,
    this.nearestCity = '',
    this.state = '',
    this.pl = '',
    this.offset = '',
    this.duplex = '',
    this.use = '',
    this.status = '',
    this.county = '',
    this.landmark = '',
    this.mode = '',
    this.distanceKm = -1,
  });
}

/// Exception thrown when RepeaterBook API rate limit is hit.
class RepeaterBookRateLimitException implements Exception {
  @override
  String toString() =>
      'RepeaterBook API rate limit reached. Please wait and try again.';
}

/// HTTP client for querying the RepeaterBook API.
///
/// Port of HTCommander.Core/Utils/RepeaterBookClient.cs
class RepeaterBookClient {
  static const String _northAmericaUrl =
      'https://www.repeaterbook.com/api/export.php';
  static const String _rowUrl =
      'https://www.repeaterbook.com/api/exportROW.php';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent =
        'HTCommander-X/1.0 (https://github.com/dikei100/HTCommander-X)';

  /// Searches RepeaterBook for repeaters in a given country/state.
  Future<List<RepeaterBookEntry>> search(
    String country,
    String state, {
    String? city,
  }) async {
    final isNorthAmerica = country == 'United States' || country == 'Canada';
    final baseUrl = isNorthAmerica ? _northAmericaUrl : _rowUrl;

    final params = <String, String>{
      'country': country,
      'state': state,
    };
    if (city != null && city.trim().isNotEmpty) {
      params['city'] = city;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: params);
    final request = await _http.getUrl(uri);
    final response = await request.close();

    if (response.statusCode == 429 || response.statusCode == 503) {
      await response.drain<void>();
      throw RepeaterBookRateLimitException();
    }

    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException(
          'RepeaterBook returned status ${response.statusCode}');
    }

    final json = await response.transform(utf8.decoder).join();
    return _parseJson(json);
  }

  List<RepeaterBookEntry> _parseJson(String json) {
    if (json.trim().isEmpty) return [];

    final doc = jsonDecode(json);
    if (doc is! Map) return [];

    final results = doc['results'];
    if (results is! List) return [];

    final entries = <RepeaterBookEntry>[];
    for (final el in results) {
      if (el is! Map) continue;
      try {
        final entry = RepeaterBookEntry(
          callsign: _getString(el, 'Callsign'),
          frequency: _getDouble(el, 'Frequency'),
          inputFreq: _getDouble(el, 'Input Freq'),
          latitude: _getDouble(el, 'Lat'),
          longitude: _getDouble(el, 'Long'),
          nearestCity: _getString(el, 'Nearest City'),
          state: _getString(el, 'State'),
          pl: _getString(el, 'PL'),
          offset: _getString(el, 'Offset'),
          duplex: _getString(el, 'Duplex'),
          use: _getString(el, 'Use'),
          status: _getString(el, 'Operational Status'),
          county: _getString(el, 'County'),
          landmark: _getString(el, 'Landmark'),
          mode: _getString(el, 'FM Analog'),
        );

        // Fallback for status field
        if (entry.status.isEmpty) {
          entry.status = _getString(el, 'Status');
        }

        // Determine mode
        if (entry.mode.isEmpty) {
          if (_getString(el, 'DMR').isNotEmpty) {
            entry.mode = 'DMR';
          } else if (_getString(el, 'D-Star').isNotEmpty) {
            entry.mode = 'D-Star';
          } else {
            entry.mode = 'FM';
          }
        } else {
          entry.mode = 'FM';
        }

        if (entry.frequency > 0) entries.add(entry);
      } catch (_) {
        // Skip malformed entries
      }
    }
    return entries;
  }

  static String _getString(Map el, String prop) {
    final val = el[prop];
    if (val is String) return val;
    if (val is num) return val.toString();
    return '';
  }

  static double _getDouble(Map el, String prop) {
    final val = el[prop];
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0;
    return 0;
  }

  /// Calculates distances from a reference point to all entries.
  static void calculateDistances(
      List<RepeaterBookEntry> entries, double lat, double lon) {
    for (final entry in entries) {
      if (entry.latitude == 0 && entry.longitude == 0) {
        entry.distanceKm = -1;
        continue;
      }
      entry.distanceKm =
          _haversine(lat, lon, entry.latitude, entry.longitude);
    }
  }

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Parses a RepeaterBook CSV export file.
  static List<RepeaterBookEntry> parseCsvExport(String filePath) {
    final results = <RepeaterBookEntry>[];
    List<String> lines;
    try {
      lines = File(filePath).readAsLinesSync();
    } catch (_) {
      return results;
    }
    if (lines.length < 2) return results;

    final headers = <String, int>{};
    final headerParts = lines[0].split(',');
    for (var i = 0; i < headerParts.length; i++) {
      headers[headerParts[i].trim().replaceAll('"', '')] = i;
    }

    for (var i = 1; i < lines.length; i++) {
      try {
        final parts = _splitCsvLine(lines[i]);
        final entry = RepeaterBookEntry();

        entry.frequency = _getCsvDouble(parts, headers, 'Frequency') > 0
            ? _getCsvDouble(parts, headers, 'Frequency')
            : _getCsvDouble(parts, headers, 'Frequency Output');
        entry.inputFreq = _getCsvDouble(parts, headers, 'Input Freq') > 0
            ? _getCsvDouble(parts, headers, 'Input Freq')
            : _getCsvDouble(parts, headers, 'Frequency Input');
        entry.callsign = _getCsvString(parts, headers, 'Callsign');
        if (entry.callsign.isEmpty) {
          entry.callsign = _getCsvString(parts, headers, 'Description');
        }
        entry.nearestCity = _getCsvString(parts, headers, 'Nearest City');
        if (entry.nearestCity.isEmpty) {
          entry.nearestCity = _getCsvString(parts, headers, 'City');
        }
        entry.state = _getCsvString(parts, headers, 'State');
        entry.county = _getCsvString(parts, headers, 'County');
        entry.latitude = _getCsvDouble(parts, headers, 'Lat');
        entry.longitude = _getCsvDouble(parts, headers, 'Long');
        entry.use = _getCsvString(parts, headers, 'Use');
        entry.status =
            _getCsvString(parts, headers, 'Operational Status');
        if (entry.status.isEmpty) {
          entry.status = _getCsvString(parts, headers, 'Status');
        }

        // Tone
        entry.pl = _getCsvString(parts, headers, 'PL');
        if (entry.pl.isEmpty) {
          var plTone = _getCsvString(parts, headers, 'PL Input Tone');
          if (plTone.endsWith(' PL')) {
            plTone = plTone.substring(0, plTone.length - 3);
          }
          entry.pl = plTone;
        }

        entry.duplex = _getCsvString(parts, headers, 'Duplex');
        entry.offset = _getCsvString(parts, headers, 'Offset');

        var mode = _getCsvString(parts, headers, 'Mode');
        if (mode.isEmpty) mode = 'FM';
        entry.mode = mode == 'FMN' ? 'FM' : mode;

        if (entry.frequency > 0) results.add(entry);
      } catch (_) {
        // Skip malformed lines
      }
    }
    return results;
  }

  static List<String> _splitCsvLine(String line) {
    final parts = <String>[];
    var inQuotes = false;
    final current = StringBuffer();
    for (final c in line.runes) {
      final ch = String.fromCharCode(c);
      if (ch == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (ch == ',' && !inQuotes) {
        parts.add(current.toString().trim());
        current.clear();
        continue;
      }
      current.write(ch);
    }
    parts.add(current.toString().trim());
    return parts;
  }

  static String _getCsvString(
      List<String> parts, Map<String, int> headers, String key) {
    final idx = headers[key];
    if (idx != null && idx < parts.length) return parts[idx].trim();
    return '';
  }

  static double _getCsvDouble(
      List<String> parts, Map<String, int> headers, String key) {
    final val = _getCsvString(parts, headers, key);
    return double.tryParse(val) ?? 0;
  }

  /// Converts a RepeaterBookEntry to a RadioChannelInfo for radio programming.
  static RadioChannelInfo? toRadioChannel(
      RepeaterBookEntry entry, int channelSlot) {
    final mode = (entry.mode).trim();
    // Skip unsupported digital modes
    if (['DMR', 'D-Star', 'P25', 'NXDN', 'System Fusion']
        .any((m) => m.toLowerCase() == mode.toLowerCase())) {
      return null;
    }

    final rxHz = (entry.frequency * 1000000).round();
    if (rxHz <= 0 || rxHz > 0x7FFFFFFF) return null;

    var txHz = rxHz;
    if (entry.inputFreq > 0) {
      final txCalc = (entry.inputFreq * 1000000).round();
      txHz = (txCalc > 0 && txCalc <= 0x7FFFFFFF) ? txCalc : rxHz;
    }
    if (rxHz == 0) return null;

    // Mode and bandwidth
    RadioModulationType modType;
    RadioBandwidthType bw;
    if (mode.toLowerCase() == 'am') {
      modType = RadioModulationType.am;
      bw = RadioBandwidthType.wide;
    } else if (mode.toLowerCase() == 'fmn') {
      modType = RadioModulationType.fm;
      bw = RadioBandwidthType.narrow;
    } else {
      modType = RadioModulationType.fm;
      bw = RadioBandwidthType.wide;
    }

    // CTCSS tone (PL field, stored as Hz × 100)
    var toneValue = 0;
    var pl = entry.pl.trim();
    if (pl.endsWith(' PL')) pl = pl.substring(0, pl.length - 3);
    final toneHz = double.tryParse(pl);
    if (toneHz != null && toneHz > 0) {
      toneValue = (toneHz * 100).round();
    }

    // Name (truncated to 10 chars)
    var name = entry.callsign.trim();
    if (name.length > 10) name = name.substring(0, 10);

    final ch = RadioChannelInfo();
    ch.channelId = channelSlot;
    ch.rxFreq = rxHz;
    ch.txFreq = txHz;
    ch.rxMod = modType;
    ch.txMod = modType;
    ch.bandwidth = bw;
    ch.txSubAudio = toneValue;
    ch.rxSubAudio = toneValue;
    ch.nameStr = name;
    ch.scan = false;
    ch.txAtMaxPower = true;
    ch.txAtMedPower = false;
    ch.txDisable = false;
    ch.mute = false;
    ch.talkAround = false;
    ch.preDeEmphBypass = false;

    return ch;
  }

  /// Country → State/Province arrays for RepeaterBook queries.
  static const Map<String, List<String>> countries = {
    'United States': [
      'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado',
      'Connecticut', 'Delaware', 'District of Columbia', 'Florida', 'Georgia',
      'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky',
      'Louisiana', 'Maine', 'Maryland', 'Massachusetts', 'Michigan',
      'Minnesota', 'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada',
      'New Hampshire', 'New Jersey', 'New Mexico', 'New York',
      'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon',
      'Pennsylvania', 'Rhode Island', 'South Carolina', 'South Dakota',
      'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington',
      'West Virginia', 'Wisconsin', 'Wyoming', 'Puerto Rico', 'Guam',
      'U.S. Virgin Islands', 'American Samoa',
    ],
    'Canada': [
      'Alberta', 'British Columbia', 'Manitoba', 'New Brunswick',
      'Newfoundland and Labrador', 'Northwest Territories', 'Nova Scotia',
      'Nunavut', 'Ontario', 'Prince Edward Island', 'Quebec', 'Saskatchewan',
      'Yukon',
    ],
    'Mexico': [],
    'United Kingdom': [],
    'Germany': [],
    'France': [],
    'Italy': [],
    'Spain': [],
    'Australia': [
      'Australian Capital Territory', 'New South Wales', 'Northern Territory',
      'Queensland', 'South Australia', 'Tasmania', 'Victoria',
      'Western Australia',
    ],
    'New Zealand': [],
    'Japan': [],
    'South Korea': [],
    'Brazil': [],
    'Argentina': [],
    'Chile': [],
    'South Africa': [],
    'India': [],
    'Thailand': [],
    'Philippines': [],
    'Indonesia': [],
    'Netherlands': [],
    'Belgium': [],
    'Switzerland': [],
    'Austria': [],
    'Poland': [],
    'Czech Republic': [],
    'Sweden': [],
    'Norway': [],
    'Denmark': [],
    'Finland': [],
    'Portugal': [],
    'Greece': [],
    'Turkey': [],
    'Israel': [],
  };

  void dispose() {
    _http.close();
  }
}
