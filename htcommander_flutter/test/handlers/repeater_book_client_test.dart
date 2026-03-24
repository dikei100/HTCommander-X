import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/handlers/repeater_book_client.dart';
import 'package:htcommander_flutter/radio/radio_enums.dart';

void main() {
  group('RepeaterBookClient.calculateDistances', () {
    test('calculates distance between two known points', () {
      final entries = [
        RepeaterBookEntry(
          callsign: 'W1ABC',
          frequency: 146.940,
          latitude: 40.7128,
          longitude: -74.0060,
        ),
      ];

      // Distance from NYC to itself should be 0
      RepeaterBookClient.calculateDistances(entries, 40.7128, -74.0060);
      expect(entries[0].distanceKm, closeTo(0.0, 0.1));
    });

    test('calculates reasonable distance between two cities', () {
      final entries = [
        RepeaterBookEntry(
          callsign: 'W6ABC',
          frequency: 146.940,
          latitude: 34.0522,   // Los Angeles
          longitude: -118.2437,
        ),
      ];

      // NYC to LA: ~3944 km
      RepeaterBookClient.calculateDistances(entries, 40.7128, -74.0060);
      expect(entries[0].distanceKm, closeTo(3944, 50));
    });

    test('sets -1 for entries with zero coordinates', () {
      final entries = [
        RepeaterBookEntry(
          callsign: 'W1ABC',
          frequency: 146.940,
          latitude: 0,
          longitude: 0,
        ),
      ];

      RepeaterBookClient.calculateDistances(entries, 40.7128, -74.0060);
      expect(entries[0].distanceKm, equals(-1));
    });
  });

  group('RepeaterBookClient.toRadioChannel', () {
    test('converts FM repeater to RadioChannelInfo', () {
      final entry = RepeaterBookEntry(
        callsign: 'W1AW',
        frequency: 146.940,
        inputFreq: 146.340,
        pl: '100.0',
        mode: 'FM',
      );

      final ch = RepeaterBookClient.toRadioChannel(entry, 0);
      expect(ch, isNotNull);
      expect(ch!.rxFreq, equals(146940000));
      expect(ch.txFreq, equals(146340000));
      expect(ch.txSubAudio, equals(10000)); // 100.0 Hz * 100
      expect(ch.rxSubAudio, equals(10000));
      expect(ch.rxMod, equals(RadioModulationType.fm));
      expect(ch.bandwidth, equals(RadioBandwidthType.wide));
      expect(ch.nameStr, equals('W1AW'));
    });

    test('rejects DMR entries', () {
      final entry = RepeaterBookEntry(
        callsign: 'W1DMR',
        frequency: 146.940,
        mode: 'DMR',
      );
      expect(RepeaterBookClient.toRadioChannel(entry, 0), isNull);
    });

    test('rejects D-Star entries', () {
      final entry = RepeaterBookEntry(
        callsign: 'W1DST',
        frequency: 146.940,
        mode: 'D-Star',
      );
      expect(RepeaterBookClient.toRadioChannel(entry, 0), isNull);
    });

    test('handles PL tone with " PL" suffix', () {
      final entry = RepeaterBookEntry(
        callsign: 'W1AW',
        frequency: 146.940,
        inputFreq: 146.340,
        pl: '88.5 PL',
        mode: 'FM',
      );

      final ch = RepeaterBookClient.toRadioChannel(entry, 0);
      expect(ch, isNotNull);
      expect(ch!.txSubAudio, equals(8850));
    });

    test('truncates long callsigns to 10 chars', () {
      final entry = RepeaterBookEntry(
        callsign: 'VERYLONGCALLSIGN',
        frequency: 146.940,
        mode: 'FM',
      );

      final ch = RepeaterBookClient.toRadioChannel(entry, 0);
      expect(ch, isNotNull);
      expect(ch!.nameStr.length, equals(10));
    });

    test('uses simplex when no input freq', () {
      final entry = RepeaterBookEntry(
        callsign: 'W1AW',
        frequency: 146.520,
        inputFreq: 0,
        mode: 'FM',
      );

      final ch = RepeaterBookClient.toRadioChannel(entry, 0);
      expect(ch, isNotNull);
      expect(ch!.txFreq, equals(ch.rxFreq));
    });
  });

  group('RepeaterBookClient.parseCsvExport', () {
    test('countries map has US states', () {
      expect(RepeaterBookClient.countries['United States'], isNotNull);
      expect(RepeaterBookClient.countries['United States']!.length, equals(55));
      expect(
          RepeaterBookClient.countries['United States']!,
          contains('California'));
    });

    test('countries map has Canadian provinces', () {
      expect(RepeaterBookClient.countries['Canada'], isNotNull);
      expect(RepeaterBookClient.countries['Canada']!, contains('Ontario'));
    });
  });
}
