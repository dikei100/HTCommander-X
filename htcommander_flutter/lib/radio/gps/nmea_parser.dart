// NMEA 0183 sentence parser with support for GGA, RMC, GSA, GSV, VTG, GLL,
// and ZDA sentence types.
//
// Port of HTCommander.Core/Gps/Nmea/ (NmeaParser.cs, NmeaConvert.cs,
// SentenceDecoder.cs, and all sentence types).

// ---------------------------------------------------------------------------
// NmeaConvert — helper methods shared across sentence decoders
// ---------------------------------------------------------------------------

/// Converts an NMEA latitude/longitude value (e.g. "4807.038") and a
/// hemisphere indicator ('N','S','E','W') to decimal degrees.
double? nmeaToDecimalDegrees(String value, String hemisphere) {
  if (value.isEmpty || hemisphere.isEmpty) return null;
  final raw = double.tryParse(value);
  if (raw == null) return null;

  // NMEA format: DDDMM.MMMMM (degrees * 100 + minutes)
  final degrees = raw ~/ 100;
  final minutes = raw - degrees * 100;
  var dec = degrees + minutes / 60.0;

  if (hemisphere == 'S' || hemisphere == 'W') dec = -dec;
  return dec;
}

/// Parses an NMEA UTC time field (HHMMSS.sss) into a [Duration].
Duration? nmeaToUtcTime(String value) {
  if (value.length < 6) return null;
  final h = int.tryParse(value.substring(0, 2));
  final m = int.tryParse(value.substring(2, 4));
  final s = double.tryParse(value.substring(4));
  if (h == null || m == null || s == null) return null;
  final sec = s.truncate();
  final ms = ((s - sec) * 1000).round();
  return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
}

/// Parses an NMEA date field (DDMMYY) into a [DateTime] (date-only, UTC).
DateTime? nmeaToDate(String value) {
  if (value.length < 6) return null;
  final day = int.tryParse(value.substring(0, 2));
  final month = int.tryParse(value.substring(2, 4));
  var year = int.tryParse(value.substring(4, 6));
  if (day == null || month == null || year == null) return null;
  year += year < 80 ? 2000 : 1900;
  try {
    return DateTime.utc(year, month, day);
  } catch (_) {
    return null;
  }
}

double? nmeaToDouble(String value) {
  if (value.isEmpty) return null;
  return double.tryParse(value);
}

int? nmeaToInt(String value) {
  if (value.isEmpty) return null;
  return int.tryParse(value);
}

/// Safe field access — returns '' for out-of-bounds indices.
String _f(List<String> fields, int index) {
  if (index < 0 || index >= fields.length) return '';
  return fields[index];
}

// ---------------------------------------------------------------------------
// NmeaParser — validates and splits raw NMEA 0183 sentences
// ---------------------------------------------------------------------------

/// Result of parsing a raw NMEA line.
class NmeaParseResult {
  final String sentenceId;
  final List<String> fields;
  NmeaParseResult(this.sentenceId, this.fields);
}

/// Tries to parse a raw NMEA line into its sentence identifier and data
/// fields. Returns null when the line is malformed or the checksum is invalid.
NmeaParseResult? nmeaTryParse(String line) {
  line = line.trim();
  if (line.length < 6 || (line[0] != '\$' && line[0] != '!')) return null;

  // Split off the checksum (after '*')
  final starIndex = line.lastIndexOf('*');
  String body;
  if (starIndex > 0 && starIndex < line.length - 1) {
    final checksumHex = line.substring(starIndex + 1);
    body = line.substring(1, starIndex); // skip leading '$'
    if (!_validateChecksum(body, checksumHex)) return null;
  } else {
    // No checksum — accept anyway
    body = line.substring(1);
  }

  final parts = body.split(',');
  if (parts.isEmpty) return null;

  return NmeaParseResult(parts[0], parts);
}

bool _validateChecksum(String body, String expectedHex) {
  if (expectedHex.length < 2) return false;
  var computed = 0;
  for (var i = 0; i < body.length; i++) {
    computed ^= body.codeUnitAt(i);
  }
  computed &= 0xFF;
  final expected = int.tryParse(expectedHex.substring(0, 2), radix: 16);
  return expected != null && computed == expected;
}

// ---------------------------------------------------------------------------
// Sentence data classes
// ---------------------------------------------------------------------------

/// GGA - Global Positioning System Fix Data.
class GgaSentence {
  final Duration? utcTime;
  final double? latitude;
  final double? longitude;
  final int? fixQuality;
  final int? satelliteCount;
  final double? hdop;
  final double? altitudeMeters;
  final double? geoidSeparation;

  GgaSentence({
    this.utcTime,
    this.latitude,
    this.longitude,
    this.fixQuality,
    this.satelliteCount,
    this.hdop,
    this.altitudeMeters,
    this.geoidSeparation,
  });

  String get fixQualityDescription {
    switch (fixQuality) {
      case 0:
        return 'Invalid';
      case 1:
        return 'GPS Fix (SPS)';
      case 2:
        return 'DGPS Fix';
      case 3:
        return 'PPS Fix';
      case 4:
        return 'RTK Fixed';
      case 5:
        return 'RTK Float';
      case 6:
        return 'Estimated (DR)';
      case 7:
        return 'Manual Input';
      case 8:
        return 'Simulation';
      default:
        return 'Unknown';
    }
  }

  static GgaSentence parse(List<String> fields) => GgaSentence(
        utcTime: nmeaToUtcTime(_f(fields, 1)),
        latitude: nmeaToDecimalDegrees(_f(fields, 2), _f(fields, 3)),
        longitude: nmeaToDecimalDegrees(_f(fields, 4), _f(fields, 5)),
        fixQuality: nmeaToInt(_f(fields, 6)),
        satelliteCount: nmeaToInt(_f(fields, 7)),
        hdop: nmeaToDouble(_f(fields, 8)),
        altitudeMeters: nmeaToDouble(_f(fields, 9)),
        geoidSeparation: nmeaToDouble(_f(fields, 11)),
      );

  @override
  String toString() =>
      '[GGA] Fix=$fixQualityDescription  Lat=${latitude?.toStringAsFixed(6)}  '
      'Lon=${longitude?.toStringAsFixed(6)}  Alt=${altitudeMeters?.toStringAsFixed(1)}m  '
      'Sats=$satelliteCount  HDOP=${hdop?.toStringAsFixed(1)}';
}

/// RMC - Recommended Minimum Specific GNSS Data.
class RmcSentence {
  final Duration? utcTime;
  final String? status;
  final double? latitude;
  final double? longitude;
  final double? speedKnots;
  final double? trackAngle;
  final DateTime? date;
  final double? magneticVariation;
  final String? magneticDirection;
  final String? mode;

  RmcSentence({
    this.utcTime,
    this.status,
    this.latitude,
    this.longitude,
    this.speedKnots,
    this.trackAngle,
    this.date,
    this.magneticVariation,
    this.magneticDirection,
    this.mode,
  });

  double? get speedKph =>
      speedKnots != null ? speedKnots! * 1.852 : null;

  bool get isActive => status == 'A';

  static RmcSentence parse(List<String> fields) => RmcSentence(
        utcTime: nmeaToUtcTime(_f(fields, 1)),
        status: _f(fields, 2).isNotEmpty ? _f(fields, 2) : null,
        latitude: nmeaToDecimalDegrees(_f(fields, 3), _f(fields, 4)),
        longitude: nmeaToDecimalDegrees(_f(fields, 5), _f(fields, 6)),
        speedKnots: nmeaToDouble(_f(fields, 7)),
        trackAngle: nmeaToDouble(_f(fields, 8)),
        date: nmeaToDate(_f(fields, 9)),
        magneticVariation: nmeaToDouble(_f(fields, 10)),
        magneticDirection:
            _f(fields, 11).isNotEmpty ? _f(fields, 11) : null,
        mode: _f(fields, 12).isNotEmpty ? _f(fields, 12) : null,
      );

  @override
  String toString() =>
      '[RMC] Date=$date  Status=${isActive ? "Active" : "Void"}  '
      'Lat=${latitude?.toStringAsFixed(6)}  Lon=${longitude?.toStringAsFixed(6)}  '
      'Speed=${speedKnots?.toStringAsFixed(1)}kn  Track=${trackAngle?.toStringAsFixed(1)}';
}

/// GSA - GNSS DOP and Active Satellites.
class GsaSentence {
  final String? selectionMode;
  final int? fixType;
  final List<int> satellitePrns;
  final double? pdop;
  final double? hdop;
  final double? vdop;

  GsaSentence({
    this.selectionMode,
    this.fixType,
    this.satellitePrns = const [],
    this.pdop,
    this.hdop,
    this.vdop,
  });

  String get fixDescription {
    switch (fixType) {
      case 1:
        return 'No Fix';
      case 2:
        return '2D Fix';
      case 3:
        return '3D Fix';
      default:
        return 'Unknown';
    }
  }

  static GsaSentence parse(List<String> fields) {
    final prns = <int>[];
    for (var i = 3; i <= 14 && i < fields.length; i++) {
      final prn = nmeaToInt(fields[i]);
      if (prn != null) prns.add(prn);
    }

    return GsaSentence(
      selectionMode: _f(fields, 1).isNotEmpty ? _f(fields, 1) : null,
      fixType: nmeaToInt(_f(fields, 2)),
      satellitePrns: prns,
      pdop: nmeaToDouble(_f(fields, 15)),
      hdop: nmeaToDouble(_f(fields, 16)),
      vdop: nmeaToDouble(_f(fields, 17)),
    );
  }

  @override
  String toString() =>
      '[GSA] Fix=$fixDescription  Mode=$selectionMode  '
      'PDOP=${pdop?.toStringAsFixed(1)}  HDOP=${hdop?.toStringAsFixed(1)}  '
      'VDOP=${vdop?.toStringAsFixed(1)}  SVs=$satellitePrns';
}

/// Single satellite info within a GSV sentence.
class SatelliteInfo {
  final int prn;
  final int? elevationDeg;
  final int? azimuthDeg;
  final int? snr;

  SatelliteInfo({
    required this.prn,
    this.elevationDeg,
    this.azimuthDeg,
    this.snr,
  });

  @override
  String toString() =>
      'PRN $prn: El=$elevationDeg  Az=$azimuthDeg  SNR=${snr ?? "--"}dB';
}

/// GSV - GNSS Satellites in View.
class GsvSentence {
  final int? totalMessages;
  final int? messageNumber;
  final int? satellitesInView;
  final List<SatelliteInfo> satellites;

  GsvSentence({
    this.totalMessages,
    this.messageNumber,
    this.satellitesInView,
    this.satellites = const [],
  });

  static GsvSentence parse(List<String> fields) {
    final sats = <SatelliteInfo>[];
    var idx = 4;
    while (idx + 3 < fields.length) {
      final prn = nmeaToInt(fields[idx]);
      if (prn == null) break;
      sats.add(SatelliteInfo(
        prn: prn,
        elevationDeg: nmeaToInt(_f(fields, idx + 1)),
        azimuthDeg: nmeaToInt(_f(fields, idx + 2)),
        snr: nmeaToInt(_f(fields, idx + 3)),
      ));
      idx += 4;
    }

    return GsvSentence(
      totalMessages: nmeaToInt(_f(fields, 1)),
      messageNumber: nmeaToInt(_f(fields, 2)),
      satellitesInView: nmeaToInt(_f(fields, 3)),
      satellites: sats,
    );
  }

  @override
  String toString() =>
      '[GSV] Msg $messageNumber/$totalMessages  InView=$satellitesInView  '
      '${satellites.join("  |  ")}';
}

/// VTG - Track Made Good and Ground Speed.
class VtgSentence {
  final double? trackTrue;
  final double? trackMagnetic;
  final double? speedKnots;
  final double? speedKph;
  final String? mode;

  VtgSentence({
    this.trackTrue,
    this.trackMagnetic,
    this.speedKnots,
    this.speedKph,
    this.mode,
  });

  static VtgSentence parse(List<String> fields) => VtgSentence(
        trackTrue: nmeaToDouble(_f(fields, 1)),
        trackMagnetic: nmeaToDouble(_f(fields, 3)),
        speedKnots: nmeaToDouble(_f(fields, 5)),
        speedKph: nmeaToDouble(_f(fields, 7)),
        mode: _f(fields, 9).isNotEmpty ? _f(fields, 9) : null,
      );

  @override
  String toString() =>
      '[VTG] TrackTrue=${trackTrue?.toStringAsFixed(1)}  '
      'TrackMag=${trackMagnetic?.toStringAsFixed(1)}  '
      'Speed=${speedKnots?.toStringAsFixed(1)}kn (${speedKph?.toStringAsFixed(1)}km/h)  '
      'Mode=$mode';
}

/// GLL - Geographic Position - Latitude/Longitude.
class GllSentence {
  final double? latitude;
  final double? longitude;
  final Duration? utcTime;
  final String? status;
  final String? mode;

  GllSentence({
    this.latitude,
    this.longitude,
    this.utcTime,
    this.status,
    this.mode,
  });

  bool get isValid => status == 'A';

  static GllSentence parse(List<String> fields) => GllSentence(
        latitude: nmeaToDecimalDegrees(_f(fields, 1), _f(fields, 2)),
        longitude: nmeaToDecimalDegrees(_f(fields, 3), _f(fields, 4)),
        utcTime: nmeaToUtcTime(_f(fields, 5)),
        status: _f(fields, 6).isNotEmpty ? _f(fields, 6) : null,
        mode: _f(fields, 7).isNotEmpty ? _f(fields, 7) : null,
      );

  @override
  String toString() =>
      '[GLL] Lat=${latitude?.toStringAsFixed(6)}  '
      'Lon=${longitude?.toStringAsFixed(6)}  '
      'Status=${isValid ? "Valid" : "Void"}';
}

/// ZDA - Time & Date.
class ZdaSentence {
  final Duration? utcTime;
  final int? day;
  final int? month;
  final int? year;
  final int? localZoneHours;
  final int? localZoneMinutes;

  ZdaSentence({
    this.utcTime,
    this.day,
    this.month,
    this.year,
    this.localZoneHours,
    this.localZoneMinutes,
  });

  static ZdaSentence parse(List<String> fields) => ZdaSentence(
        utcTime: nmeaToUtcTime(_f(fields, 1)),
        day: nmeaToInt(_f(fields, 2)),
        month: nmeaToInt(_f(fields, 3)),
        year: nmeaToInt(_f(fields, 4)),
        localZoneHours: nmeaToInt(_f(fields, 5)),
        localZoneMinutes: nmeaToInt(_f(fields, 6)),
      );

  @override
  String toString() =>
      '[ZDA] $year-$month-$day  $utcTime UTC  '
      'LocalOffset=$localZoneHours:$localZoneMinutes';
}

// ---------------------------------------------------------------------------
// SentenceDecoder — routes parsed sentences to the appropriate decoder
// ---------------------------------------------------------------------------

/// Decodes a raw NMEA line and returns a formatted string, or null if the
/// sentence type is not supported.
String? nmeaDecode(String rawLine) {
  final result = nmeaTryParse(rawLine);
  if (result == null) return null;

  // The talker ID is the first two characters (e.g. "GP", "GN", "GL").
  // The sentence type is the remaining characters.
  final id = result.sentenceId;
  final type = id.length >= 5 ? id.substring(2) : id;

  try {
    switch (type) {
      case 'GGA':
        return GgaSentence.parse(result.fields).toString();
      case 'RMC':
        return RmcSentence.parse(result.fields).toString();
      case 'GSA':
        return GsaSentence.parse(result.fields).toString();
      case 'GSV':
        return GsvSentence.parse(result.fields).toString();
      case 'VTG':
        return VtgSentence.parse(result.fields).toString();
      case 'GLL':
        return GllSentence.parse(result.fields).toString();
      case 'ZDA':
        return ZdaSentence.parse(result.fields).toString();
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}
