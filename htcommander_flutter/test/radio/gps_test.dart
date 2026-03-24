import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/radio/gps/nmea_parser.dart';

void main() {
  group('NmeaConvert', () {
    group('nmeaToDecimalDegrees', () {
      test('parses north latitude', () {
        // 48 degrees 7.038 minutes N = 48.1173 degrees
        final result = nmeaToDecimalDegrees('4807.038', 'N');
        expect(result, isNotNull);
        expect(result!, closeTo(48.1173, 0.0001));
      });

      test('parses south latitude', () {
        final result = nmeaToDecimalDegrees('3347.9640', 'S');
        expect(result, isNotNull);
        expect(result!, closeTo(-33.79940, 0.0001));
      });

      test('parses west longitude', () {
        final result = nmeaToDecimalDegrees('01131.000', 'W');
        expect(result, isNotNull);
        expect(result!, closeTo(-11.51667, 0.001));
      });

      test('parses east longitude', () {
        final result = nmeaToDecimalDegrees('15113.123', 'E');
        expect(result, isNotNull);
        expect(result!, closeTo(151.21872, 0.001));
      });

      test('returns null for empty value', () {
        expect(nmeaToDecimalDegrees('', 'N'), isNull);
      });

      test('returns null for empty hemisphere', () {
        expect(nmeaToDecimalDegrees('4807.038', ''), isNull);
      });

      test('returns null for invalid number', () {
        expect(nmeaToDecimalDegrees('notanumber', 'N'), isNull);
      });
    });

    group('nmeaToUtcTime', () {
      test('parses time with fractional seconds', () {
        final result = nmeaToUtcTime('123519.00');
        expect(result, isNotNull);
        expect(result!.inHours, 12);
        expect(result.inMinutes % 60, 35);
        expect(result.inSeconds % 60, 19);
      });

      test('parses time with milliseconds', () {
        final result = nmeaToUtcTime('092725.123');
        expect(result, isNotNull);
        expect(result!.inHours, 9);
        expect(result.inMinutes % 60, 27);
        expect(result.inSeconds % 60, 25);
        expect(result.inMilliseconds % 1000, 123);
      });

      test('returns null for short string', () {
        expect(nmeaToUtcTime('123'), isNull);
      });

      test('returns null for empty string', () {
        expect(nmeaToUtcTime(''), isNull);
      });
    });

    group('nmeaToDate', () {
      test('parses date in 2000s', () {
        final result = nmeaToDate('230394');
        expect(result, isNotNull);
        expect(result!.year, 1994);
        expect(result.month, 3);
        expect(result.day, 23);
      });

      test('parses date in 2000s (low year)', () {
        final result = nmeaToDate('150125');
        expect(result, isNotNull);
        expect(result!.year, 2025);
        expect(result.month, 1);
        expect(result.day, 15);
      });

      test('returns null for short string', () {
        expect(nmeaToDate('12'), isNull);
      });
    });

    group('nmeaToDouble', () {
      test('parses valid double', () {
        expect(nmeaToDouble('1.5'), 1.5);
      });

      test('returns null for empty string', () {
        expect(nmeaToDouble(''), isNull);
      });

      test('returns null for invalid string', () {
        expect(nmeaToDouble('abc'), isNull);
      });
    });

    group('nmeaToInt', () {
      test('parses valid int', () {
        expect(nmeaToInt('42'), 42);
      });

      test('returns null for empty string', () {
        expect(nmeaToInt(''), isNull);
      });
    });
  });

  group('NmeaParser', () {
    test('parses valid GGA sentence', () {
      const line =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*4F';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      expect(result!.sentenceId, 'GPGGA');
      expect(result.fields.length, greaterThanOrEqualTo(10));
    });

    test('rejects invalid checksum', () {
      const line =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*FF';
      final result = nmeaTryParse(line);
      expect(result, isNull);
    });

    test('rejects empty line', () {
      expect(nmeaTryParse(''), isNull);
    });

    test('rejects line without dollar prefix', () {
      expect(nmeaTryParse('GPGGA,123519'), isNull);
    });

    test('parses sentence without checksum', () {
      const line = r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      expect(result!.sentenceId, 'GPGGA');
    });

    test('parses GNRMC multi-constellation prefix', () {
      const line =
          r'$GNRMC,220516,A,5133.82,N,00042.24,W,173.8,231.8,130694,004.2,W*6E';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      expect(result!.sentenceId, 'GNRMC');
    });
  });

  group('GGA sentence', () {
    test('parses full GGA fields', () {
      const line =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*4F';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final gga = GgaSentence.parse(result!.fields);
      expect(gga.latitude, isNotNull);
      expect(gga.latitude!, closeTo(48.1173, 0.001));
      expect(gga.longitude, isNotNull);
      expect(gga.longitude!, closeTo(11.51667, 0.001));
      expect(gga.fixQuality, 1);
      expect(gga.satelliteCount, 8);
      expect(gga.hdop, closeTo(0.9, 0.01));
      expect(gga.altitudeMeters, closeTo(545.4, 0.1));
      expect(gga.geoidSeparation, closeTo(47.0, 0.1));
      expect(gga.fixQualityDescription, 'GPS Fix (SPS)');
    });
  });

  group('RMC sentence', () {
    test('parses full RMC fields', () {
      const line =
          r'$GPRMC,220516,A,5133.82,N,00042.24,W,173.8,231.8,130694,004.2,W*70';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final rmc = RmcSentence.parse(result!.fields);
      expect(rmc.isActive, isTrue);
      expect(rmc.latitude, isNotNull);
      expect(rmc.latitude!, closeTo(51.5637, 0.001));
      expect(rmc.longitude, isNotNull);
      expect(rmc.longitude!, closeTo(-0.704, 0.001));
      expect(rmc.speedKnots, closeTo(173.8, 0.1));
      expect(rmc.trackAngle, closeTo(231.8, 0.1));
      expect(rmc.date, isNotNull);
      expect(rmc.date!.year, 1994);
      expect(rmc.date!.month, 6);
      expect(rmc.date!.day, 13);
      expect(rmc.speedKph, isNotNull);
      expect(rmc.speedKph!, closeTo(173.8 * 1.852, 0.1));
    });

    test('detects void status', () {
      const line =
          r'$GPRMC,220516,V,5133.82,N,00042.24,W,173.8,231.8,130694,004.2,W*67';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final rmc = RmcSentence.parse(result!.fields);
      expect(rmc.isActive, isFalse);
    });
  });

  group('GSA sentence', () {
    test('parses GSA with satellite PRNs', () {
      const line =
          r'$GPGSA,A,3,04,05,,09,12,,,24,,,,,2.5,1.3,2.1*39';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final gsa = GsaSentence.parse(result!.fields);
      expect(gsa.selectionMode, 'A');
      expect(gsa.fixType, 3);
      expect(gsa.fixDescription, '3D Fix');
      expect(gsa.satellitePrns, contains(4));
      expect(gsa.satellitePrns, contains(5));
      expect(gsa.satellitePrns, contains(9));
      expect(gsa.satellitePrns, contains(12));
      expect(gsa.satellitePrns, contains(24));
      expect(gsa.pdop, closeTo(2.5, 0.01));
      expect(gsa.hdop, closeTo(1.3, 0.01));
      expect(gsa.vdop, closeTo(2.1, 0.01));
    });
  });

  group('GSV sentence', () {
    test('parses satellites in view', () {
      const line =
          r'$GPGSV,2,1,08,01,40,083,46,02,17,308,41,12,07,344,39,14,22,228,45*75';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final gsv = GsvSentence.parse(result!.fields);
      expect(gsv.totalMessages, 2);
      expect(gsv.messageNumber, 1);
      expect(gsv.satellitesInView, 8);
      expect(gsv.satellites.length, 4);
      expect(gsv.satellites[0].prn, 1);
      expect(gsv.satellites[0].elevationDeg, 40);
      expect(gsv.satellites[0].azimuthDeg, 83);
      expect(gsv.satellites[0].snr, 46);
    });
  });

  group('VTG sentence', () {
    test('parses track and speed', () {
      const line = r'$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*48';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final vtg = VtgSentence.parse(result!.fields);
      expect(vtg.trackTrue, closeTo(54.7, 0.1));
      expect(vtg.trackMagnetic, closeTo(34.4, 0.1));
      expect(vtg.speedKnots, closeTo(5.5, 0.1));
      expect(vtg.speedKph, closeTo(10.2, 0.1));
    });
  });

  group('GLL sentence', () {
    test('parses position', () {
      const line = r'$GPGLL,4916.45,N,12311.12,W,225444,A,*1D';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final gll = GllSentence.parse(result!.fields);
      expect(gll.isValid, isTrue);
      expect(gll.latitude, isNotNull);
      expect(gll.latitude!, closeTo(49.27417, 0.001));
      expect(gll.longitude, isNotNull);
      expect(gll.longitude!, closeTo(-123.18533, 0.001));
    });
  });

  group('ZDA sentence', () {
    test('parses date and time', () {
      const line = r'$GPZDA,201530.00,04,07,2002,00,00*60';
      final result = nmeaTryParse(line);
      expect(result, isNotNull);
      final zda = ZdaSentence.parse(result!.fields);
      expect(zda.day, 4);
      expect(zda.month, 7);
      expect(zda.year, 2002);
      expect(zda.localZoneHours, 0);
      expect(zda.localZoneMinutes, 0);
    });
  });

  group('SentenceDecoder', () {
    test('decodes GGA sentence', () {
      const line =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*4F';
      final decoded = nmeaDecode(line);
      expect(decoded, isNotNull);
      expect(decoded!, contains('[GGA]'));
      expect(decoded, contains('GPS Fix (SPS)'));
    });

    test('decodes RMC sentence', () {
      const line =
          r'$GPRMC,220516,A,5133.82,N,00042.24,W,173.8,231.8,130694,004.2,W*70';
      final decoded = nmeaDecode(line);
      expect(decoded, isNotNull);
      expect(decoded!, contains('[RMC]'));
      expect(decoded, contains('Active'));
    });

    test('returns null for unsupported sentence', () {
      const line = r'$GPTXT,01,01,02,Some text*XX';
      // This will fail checksum but also unsupported type
      expect(nmeaDecode(line), isNull);
    });

    test('returns null for invalid line', () {
      expect(nmeaDecode('garbage'), isNull);
    });
  });
}
