import '../screens/logbook_screen.dart';

/// ADIF 3.1.4 format exporter for QSO log entries.
///
/// Port of HTCommander.Core/Utils/AdifExport.cs
class AdifExport {
  /// Exports a list of QSO entries to ADIF 3.1.4 format.
  static String export(List<QsoEntry> entries) {
    final sb = StringBuffer();

    // ADIF header
    sb.writeln('ADIF Export from HTCommander-X');
    sb.writeln(
        'Generated: ${DateTime.now().toUtc().toIso8601String().substring(0, 16).replaceAll('T', ' ')} UTC');
    sb.writeln();
    _writeField(sb, 'ADIF_VER', '3.1.4');
    _writeField(sb, 'PROGRAMID', 'HTCommander-X');
    sb.writeln();
    sb.writeln('<EOH>');
    sb.writeln();

    for (final qso in entries) {
      if (qso.callsign.trim().isEmpty) continue;

      _writeField(sb, 'CALL', qso.callsign);

      // Parse dateTime string to extract date and time components
      final dt = _parseDateTime(qso.dateTime);
      if (dt != null) {
        _writeField(
            sb,
            'QSO_DATE',
            '${dt.year.toString().padLeft(4, '0')}'
                '${dt.month.toString().padLeft(2, '0')}'
                '${dt.day.toString().padLeft(2, '0')}');
        _writeField(
            sb,
            'TIME_ON',
            '${dt.hour.toString().padLeft(2, '0')}'
                '${dt.minute.toString().padLeft(2, '0')}');
      }

      if (qso.frequency.isNotEmpty) {
        // Try to format as MHz with 6 decimal places
        final freqMHz = double.tryParse(qso.frequency);
        if (freqMHz != null && freqMHz > 0) {
          _writeField(sb, 'FREQ', freqMHz.toStringAsFixed(6));
        }
      }

      if (qso.mode.isNotEmpty) _writeField(sb, 'MODE', qso.mode);
      if (qso.band.isNotEmpty) _writeField(sb, 'BAND', qso.band);
      if (qso.rstSent.isNotEmpty) _writeField(sb, 'RST_SENT', qso.rstSent);
      if (qso.rstRcvd.isNotEmpty) _writeField(sb, 'RST_RCVD', qso.rstRcvd);
      if (qso.myCall.isNotEmpty) {
        _writeField(sb, 'STATION_CALLSIGN', qso.myCall);
      }
      if (qso.notes.isNotEmpty) _writeField(sb, 'COMMENT', qso.notes);

      sb.writeln('<EOR>');
      sb.writeln();
    }

    return sb.toString();
  }

  static void _writeField(StringBuffer sb, String tag, String value) {
    if (value.isEmpty) return;
    // Sanitize: strip '<' and '>' to prevent ADIF tag injection
    final sanitized = value.replaceAll('<', '').replaceAll('>', '');
    if (sanitized.isEmpty) return;
    sb.write('<$tag:${sanitized.length}>$sanitized ');
  }

  /// Attempts to parse a date/time string in common formats.
  static DateTime? _parseDateTime(String s) {
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
