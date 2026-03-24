import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/handlers/import_utils.dart';
import 'package:htcommander_flutter/radio/radio_enums.dart';

void main() {
  group('ImportUtils CHIRP format', () {
    test('parses CHIRP CSV with simplex channel', () {
      final tmpFile = _writeTempCsv([
        'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
        '0,SIMPLEX,146.520000,,0.600000,,88.5,88.5,023,NN,FM,5.00,,5.0W',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, hasLength(1));
      expect(channels[0].nameStr, equals('SIMPLEX'));
      expect(channels[0].rxFreq, equals(146520000));
      expect(channels[0].txFreq, equals(146520000));
      expect(channels[0].rxMod, equals(RadioModulationType.fm));
      expect(channels[0].bandwidth, equals(RadioBandwidthType.wide));
      tmpFile.deleteSync();
    });

    test('parses CHIRP CSV with + duplex offset', () {
      final tmpFile = _writeTempCsv([
        'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
        '1,REPEATER,146.940000,+,0.600000,Tone,100.0,100.0,023,NN,FM,5.00,,5.0W',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, hasLength(1));
      expect(channels[0].rxFreq, equals(146940000));
      expect(channels[0].txFreq, equals(147540000));
      expect(channels[0].txSubAudio, equals(10000)); // 100.0 Hz * 100
      tmpFile.deleteSync();
    });

    test('parses CHIRP CSV with - duplex offset', () {
      final tmpFile = _writeTempCsv([
        'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
        '2,RPT-NEG,147.360000,-,0.600000,TSQL,88.5,88.5,023,NN,FM,5.00,,5.0W',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, hasLength(1));
      expect(channels[0].rxFreq, equals(147360000));
      expect(channels[0].txFreq, equals(146760000));
      // TSQL: same tone for both TX and RX
      expect(channels[0].txSubAudio, equals(8850));
      expect(channels[0].rxSubAudio, equals(8850));
      tmpFile.deleteSync();
    });

    test('parses NFM mode as narrow bandwidth', () {
      final tmpFile = _writeTempCsv([
        'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
        '3,NARROW,462.562500,,0.000000,,88.5,88.5,023,NN,NFM,5.00,,5.0W',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, hasLength(1));
      expect(channels[0].bandwidth, equals(RadioBandwidthType.narrow));
      tmpFile.deleteSync();
    });

    test('parses low power setting', () {
      final tmpFile = _writeTempCsv([
        'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
        '4,LOWPWR,146.520000,,0.000000,,88.5,88.5,023,NN,FM,5.00,,0.5W',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, hasLength(1));
      expect(channels[0].txAtMaxPower, isFalse);
      expect(channels[0].txAtMedPower, isFalse);
      tmpFile.deleteSync();
    });
  });

  group('ImportUtils native format', () {
    test('parses native HTCommander CSV', () {
      final tmpFile = _writeTempCsv([
        'title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),bandwidth(12500/25000),scan(0=OFF/1=ON),talk around(0=OFF/1=ON),pre_de_emph_bypass(0=OFF/1=ON),sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),mute(0=OFF/1=ON),rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)',
        'TEST,146520000,146520000,8850,8850,H,25000,1,0,0,0,0,0,FM,FM',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, hasLength(1));
      expect(channels[0].nameStr, equals('TEST'));
      expect(channels[0].txFreq, equals(146520000));
      expect(channels[0].rxFreq, equals(146520000));
      expect(channels[0].txSubAudio, equals(8850));
      expect(channels[0].txAtMaxPower, isTrue);
      expect(channels[0].bandwidth, equals(RadioBandwidthType.wide));
      expect(channels[0].scan, isTrue);
      tmpFile.deleteSync();
    });
  });

  group('ImportUtils export', () {
    test('exportNative roundtrips with parseNative', () {
      final tmpFile = _writeTempCsv([
        'title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),bandwidth(12500/25000),scan(0=OFF/1=ON),talk around(0=OFF/1=ON),pre_de_emph_bypass(0=OFF/1=ON),sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),mute(0=OFF/1=ON),rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)',
        'TEST,146520000,146520000,8850,8850,H,25000,1,0,0,0,0,0,FM,FM',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      final exported = ImportUtils.exportNative(channels);
      expect(exported, contains('TEST'));
      expect(exported, contains('146520000'));
      expect(exported, contains('8850'));
      tmpFile.deleteSync();
    });

    test('exportChirp generates valid CHIRP CSV', () {
      final tmpFile = _writeTempCsv([
        'title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),bandwidth(12500/25000),scan(0=OFF/1=ON),talk around(0=OFF/1=ON),pre_de_emph_bypass(0=OFF/1=ON),sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),mute(0=OFF/1=ON),rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)',
        'TEST,146520000,146520000,8850,8850,H,25000,1,0,0,0,0,0,FM,FM',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      final exported = ImportUtils.exportChirp(channels);
      expect(exported, contains('Location,Name,Frequency'));
      expect(exported, contains('146.520000'));
      tmpFile.deleteSync();
    });
  });

  group('ImportUtils empty/invalid', () {
    test('returns empty list for nonexistent file', () {
      final channels = ImportUtils.decodeChannelsFile('/nonexistent/path.csv');
      expect(channels, isEmpty);
    });

    test('returns empty list for file with only header', () {
      final tmpFile = _writeTempCsv([
        'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
      ]);
      final channels = ImportUtils.decodeChannelsFile(tmpFile.path);
      expect(channels, isEmpty);
      tmpFile.deleteSync();
    });
  });
}

File _writeTempCsv(List<String> lines) {
  final file = File('${Directory.systemTemp.path}/test_channels_${DateTime.now().millisecondsSinceEpoch}.csv');
  file.writeAsStringSync(lines.join('\n'));
  return file;
}
