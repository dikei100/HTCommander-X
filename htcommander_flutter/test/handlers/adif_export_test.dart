import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/handlers/adif_export.dart';
import 'package:htcommander_flutter/screens/logbook_screen.dart';

void main() {
  group('AdifExport', () {
    test('exports header with version and program ID', () {
      final result = AdifExport.export([]);
      expect(result, contains('ADIF Export from HTCommander-X'));
      expect(result, contains('<ADIF_VER:5>3.1.4'));
      expect(result, contains('<PROGRAMID:13>HTCommander-X'));
      expect(result, contains('<EOH>'));
    });

    test('exports QSO entry with all fields', () {
      final entries = [
        QsoEntry(
          dateTime: '2026-03-15T14:30:00',
          callsign: 'W1ABC',
          frequency: '146.520',
          mode: 'FM',
          band: '2m',
          rstSent: '59',
          rstRcvd: '57',
          myCall: 'KD2XYZ',
          notes: 'Good signal',
        ),
      ];

      final result = AdifExport.export(entries);
      expect(result, contains('<CALL:5>W1ABC'));
      expect(result, contains('<QSO_DATE:8>20260315'));
      expect(result, contains('<TIME_ON:4>1430'));
      expect(result, contains('<FREQ:10>146.520000'));
      expect(result, contains('<MODE:2>FM'));
      expect(result, contains('<BAND:2>2m'));
      expect(result, contains('<RST_SENT:2>59'));
      expect(result, contains('<RST_RCVD:2>57'));
      expect(result, contains('<STATION_CALLSIGN:6>KD2XYZ'));
      expect(result, contains('<COMMENT:11>Good signal'));
      expect(result, contains('<EOR>'));
    });

    test('skips entries with empty callsign', () {
      final entries = [
        QsoEntry(
          dateTime: '2026-03-15T14:30:00',
          callsign: '',
          frequency: '146.520',
          mode: 'FM',
          band: '2m',
          rstSent: '59',
          rstRcvd: '57',
          myCall: 'KD2XYZ',
          notes: '',
        ),
      ];

      final result = AdifExport.export(entries);
      expect(result, isNot(contains('<CALL')));
      expect(result, isNot(contains('<EOR>')));
    });

    test('skips empty optional fields', () {
      final entries = [
        QsoEntry(
          dateTime: '2026-03-15T14:30:00',
          callsign: 'W1ABC',
          frequency: '',
          mode: '',
          band: '',
          rstSent: '',
          rstRcvd: '',
          myCall: '',
          notes: '',
        ),
      ];

      final result = AdifExport.export(entries);
      expect(result, contains('<CALL:5>W1ABC'));
      expect(result, isNot(contains('<FREQ')));
      expect(result, isNot(contains('<MODE')));
      expect(result, isNot(contains('<BAND')));
    });

    test('sanitizes angle brackets in values', () {
      final entries = [
        QsoEntry(
          dateTime: '2026-03-15T14:30:00',
          callsign: 'W1ABC',
          frequency: '',
          mode: '',
          band: '',
          rstSent: '',
          rstRcvd: '',
          myCall: '',
          notes: '<script>alert(1)</script>',
        ),
      ];

      final result = AdifExport.export(entries);
      expect(result, isNot(contains('<script>')));
      expect(result, contains('scriptalert(1)/script'));
    });

    test('handles multiple QSO entries', () {
      final entries = [
        QsoEntry(
          dateTime: '2026-03-15T14:30:00',
          callsign: 'W1ABC',
          frequency: '146.520',
          mode: 'FM',
          band: '2m',
          rstSent: '59',
          rstRcvd: '59',
          myCall: 'KD2XYZ',
          notes: '',
        ),
        QsoEntry(
          dateTime: '2026-03-15T15:00:00',
          callsign: 'N2DEF',
          frequency: '440.000',
          mode: 'FM',
          band: '70cm',
          rstSent: '55',
          rstRcvd: '55',
          myCall: 'KD2XYZ',
          notes: '',
        ),
      ];

      final result = AdifExport.export(entries);
      expect('<EOR>'.allMatches(result).length, equals(2));
      expect(result, contains('<CALL:5>W1ABC'));
      expect(result, contains('<CALL:5>N2DEF'));
    });
  });
}
