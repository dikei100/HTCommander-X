import 'dart:io';

import '../radio/models/radio_channel_info.dart';
import '../radio/radio_enums.dart';

/// Channel import/export utilities.
///
/// Supports three CSV formats:
/// 1. CHIRP (Location, Name, Frequency, Mode columns)
/// 2. Native HTCommander (title, tx_freq, rx_freq columns)
/// 3. RepeaterBook export (Frequency Output, Frequency Input, Description)
///
/// Port of HTCommander.Core/ChannelImport.cs
class ImportUtils {
  /// Parses a channel CSV file and returns a list of RadioChannelInfo.
  /// Auto-detects format based on CSV headers.
  static List<RadioChannelInfo> decodeChannelsFile(String filename) {
    final channels = <RadioChannelInfo>[];
    List<String> lines;
    try {
      lines = File(filename).readAsLinesSync();
    } catch (_) {
      return channels;
    }
    if (lines.length < 2) return channels;

    final headers = <String, int>{};
    final headerParts = lines[0].split(',');
    for (var i = 0; i < headerParts.length; i++) {
      headers[_removeQuotes(headerParts[i].trim())] = i;
    }

    // Format 1: CHIRP format
    if (headers.containsKey('Location') &&
        headers.containsKey('Name') &&
        headers.containsKey('Frequency') &&
        headers.containsKey('Mode')) {
      for (var i = 1; i < lines.length; i++) {
        try {
          final c = _parseChirp(lines[i].split(','), headers);
          if (c != null) channels.add(c);
        } catch (_) {}
      }
    }

    // Format 2: Native HTCommander format
    if (headers.containsKey('title') &&
        headers.containsKey('tx_freq') &&
        headers.containsKey('rx_freq')) {
      for (var i = 1; i < lines.length; i++) {
        try {
          final c = _parseNative(lines[i].split(','), headers);
          if (c != null) channels.add(c);
        } catch (_) {}
      }
    }

    // Format 3: RepeaterBook export
    if (headers.containsKey('Frequency Output') &&
        headers.containsKey('Frequency Input') &&
        headers.containsKey('Description') &&
        headers.containsKey('PL Output Tone') &&
        headers.containsKey('PL Input Tone') &&
        headers.containsKey('Mode')) {
      for (var i = 1; i < lines.length; i++) {
        try {
          final c = _parseRepeaterBook(lines[i].split(','), headers);
          if (c != null) channels.add(c);
        } catch (_) {}
      }
    }

    return channels;
  }

  /// CHIRP format parser (Format 1).
  static RadioChannelInfo? _parseChirp(
      List<String> parts, Map<String, int> headers) {
    final r = RadioChannelInfo();

    r.channelId = _tryParseInt(_getValue(parts, headers, 'Location')) ?? 0;
    r.nameStr = _getValue(parts, headers, 'Name');
    final rxFreqMHz = _tryParseDouble(_getValue(parts, headers, 'Frequency'));
    r.rxFreq = rxFreqMHz != null ? (rxFreqMHz * 1000000).round() : 0;

    // Power level
    r.txAtMaxPower = true;
    r.txAtMedPower = false;
    final powerStr = _getValue(parts, headers, 'Power');
    if (powerStr.isNotEmpty && powerStr.toUpperCase().endsWith('W')) {
      final watts =
          double.tryParse(powerStr.substring(0, powerStr.length - 1));
      if (watts != null) {
        if (watts <= 1.0) {
          r.txAtMaxPower = false;
          r.txAtMedPower = false;
        } else if (watts <= 4.0) {
          r.txAtMaxPower = false;
          r.txAtMedPower = true;
        }
      }
    }

    // Duplex and offset
    final duplexValue = _getValue(parts, headers, 'Duplex');
    final offsetMHz =
        _tryParseDouble(_getValue(parts, headers, 'Offset'));

    if (duplexValue.toLowerCase() == 'split' && offsetMHz != null) {
      r.txFreq = (offsetMHz * 1000000).round();
    } else if ((duplexValue == '+' || duplexValue == '-') &&
        offsetMHz != null) {
      final offsetHz = (offsetMHz * 1000000).round();
      final sign = duplexValue == '+' ? 1 : -1;
      r.txFreq = r.rxFreq + (sign * offsetHz);
    } else {
      r.txFreq = r.rxFreq;
    }

    // Tone/sub-audio
    final toneMode = _getValue(parts, headers, 'Tone');
    r.rxSubAudio = 0;
    r.txSubAudio = 0;

    final rToneFreq =
        _tryParseDouble(_getValue(parts, headers, 'rToneFreq'));
    final cToneFreq =
        _tryParseDouble(_getValue(parts, headers, 'cToneFreq'));
    final rToneValue = rToneFreq != null ? (rToneFreq * 100).round() : 0;
    final cToneValue = cToneFreq != null ? (cToneFreq * 100).round() : 0;
    final dtcsCode = _tryParseInt(_getValue(parts, headers, 'DtcsCode'));
    final rxDtcsCode =
        _tryParseInt(_getValue(parts, headers, 'RxDtcsCode'));
    final crossMode = _getValue(parts, headers, 'CrossMode');

    switch (toneMode.toLowerCase()) {
      case 'tone':
        r.txSubAudio = rToneValue;
        r.rxSubAudio = 0;
        break;
      case 'tsql':
        r.txSubAudio = cToneValue;
        r.rxSubAudio = cToneValue;
        break;
      case 'dtcs':
        if (dtcsCode != null) {
          r.txSubAudio = dtcsCode;
          r.rxSubAudio = dtcsCode;
        }
        break;
      case 'cross':
        _parseCrossMode(
            crossMode, r, rToneValue, cToneValue, dtcsCode, rxDtcsCode);
        break;
    }

    // Mode and bandwidth
    final mode = _getValue(parts, headers, 'Mode');
    r.rxMod = RadioModulationType.fm;
    r.txMod = RadioModulationType.fm;
    r.bandwidth = RadioBandwidthType.wide;

    switch (mode.toUpperCase()) {
      case 'NFM':
        r.bandwidth = RadioBandwidthType.narrow;
        break;
      case 'AM':
        r.rxMod = RadioModulationType.am;
        r.txMod = RadioModulationType.am;
        break;
      case 'DMR':
        r.rxMod = RadioModulationType.dmr;
        r.txMod = RadioModulationType.dmr;
        r.bandwidth = RadioBandwidthType.narrow;
        break;
    }

    return r;
  }

  static void _parseCrossMode(String crossMode, RadioChannelInfo r,
      int rToneValue, int cToneValue, int? dtcsCode, int? rxDtcsCode) {
    switch (crossMode.toLowerCase()) {
      case 'tone->tone':
        r.txSubAudio = rToneValue;
        r.rxSubAudio = cToneValue;
        break;
      case 'tone->':
        r.rxSubAudio = rToneValue;
        break;
      case '->tone':
        r.txSubAudio = cToneValue;
        break;
      case 'dtcs->dtcs':
        if (dtcsCode != null) r.txSubAudio = dtcsCode;
        if (rxDtcsCode != null) r.rxSubAudio = rxDtcsCode;
        break;
      case 'tone->dtcs':
        r.txSubAudio = rToneValue;
        if (rxDtcsCode != null) r.rxSubAudio = rxDtcsCode;
        break;
      case 'dtcs->tone':
        if (dtcsCode != null) r.txSubAudio = dtcsCode;
        r.rxSubAudio = cToneValue;
        break;
      case 'dtcs->':
        if (dtcsCode != null) r.txSubAudio = dtcsCode;
        break;
      case '->dtcs':
        if (rxDtcsCode != null) r.rxSubAudio = rxDtcsCode;
        break;
    }
  }

  /// Native HTCommander format parser (Format 2).
  static RadioChannelInfo? _parseNative(
      List<String> parts, Map<String, int> headers) {
    final r = RadioChannelInfo();
    r.channelId = 0;
    r.nameStr = parts[headers['title']!];
    r.txFreq = int.parse(parts[headers['tx_freq']!]);
    r.rxFreq = int.parse(parts[headers['rx_freq']!]);
    r.txSubAudio =
        int.parse(parts[headers['tx_sub_audio(CTCSS=freq/DCS=number)']!]);
    r.rxSubAudio =
        int.parse(parts[headers['rx_sub_audio(CTCSS=freq/DCS=number)']!]);

    final power = parts[headers['tx_power(H/M/L)']!];
    r.txAtMaxPower = power == 'H';
    r.txAtMedPower = power == 'M';
    r.bandwidth =
        parts[headers['bandwidth(12500/25000)']!] == '25000'
            ? RadioBandwidthType.wide
            : RadioBandwidthType.narrow;
    r.scan = parts[headers['scan(0=OFF/1=ON)']!] == '1';
    r.talkAround = parts[headers['talk around(0=OFF/1=ON)']!] == '1';
    r.preDeEmphBypass =
        parts[headers['pre_de_emph_bypass(0=OFF/1=ON)']!] == '1';
    r.sign = parts[headers['sign(0=OFF/1=ON)']!] == '1';
    r.txDisable = parts[headers['tx_dis(0=OFF/1=ON)']!] == '1';
    r.mute = parts[headers['mute(0=OFF/1=ON)']!] == '1';

    final rxMod = parts[headers['rx_modulation(0=FM/1=AM)']!];
    r.rxMod = _parseModulation(rxMod);
    final txMod = parts[headers['tx_modulation(0=FM/1=AM)']!];
    r.txMod = _parseModulation(txMod);

    return r;
  }

  /// RepeaterBook export format parser (Format 3).
  static RadioChannelInfo? _parseRepeaterBook(
      List<String> parts, Map<String, int> headers) {
    for (var i = 0; i < parts.length; i++) {
      parts[i] = _removeQuotes(parts[i].trim());
    }

    final r = RadioChannelInfo();
    r.channelId = 0;
    r.nameStr = parts[headers['Description']!];
    if (r.nameStr.length > 10) r.nameStr = r.nameStr.substring(0, 10);

    final rxFreqMHz = _tryParseDouble(
        _getValue(parts, headers, 'Frequency Input'));
    r.rxFreq = rxFreqMHz != null ? (rxFreqMHz * 1000000).round() : 0;

    final txFreqMHz = _tryParseDouble(
        _getValue(parts, headers, 'Frequency Output'));
    r.txFreq = txFreqMHz != null ? (txFreqMHz * 1000000).round() : 0;
    if (r.rxFreq == 0) r.rxFreq = r.txFreq;
    if (r.txFreq == 0) r.txFreq = r.rxFreq;
    if (r.txFreq == 0 && r.rxFreq == 0) return null;

    final rxMod = parts[headers['Mode']!];
    switch (rxMod) {
      case 'AM':
        r.rxMod = RadioModulationType.am;
        r.bandwidth = RadioBandwidthType.wide;
        break;
      case 'FM':
        r.rxMod = RadioModulationType.fm;
        r.bandwidth = RadioBandwidthType.wide;
        break;
      case 'FMN':
        r.rxMod = RadioModulationType.fm;
        r.bandwidth = RadioBandwidthType.narrow;
        break;
      default:
        return null;
    }
    r.txMod = r.rxMod;

    var rxSub = parts[headers['PL Output Tone']!];
    var txSub = parts[headers['PL Input Tone']!];
    if (txSub.isEmpty) txSub = rxSub;
    if (rxSub.isEmpty) rxSub = txSub;

    if (rxSub.endsWith(' PL')) {
      final val = _tryParseDouble(rxSub.substring(0, rxSub.length - 3));
      r.rxSubAudio = val != null ? (val * 100).round() : 0;
    }
    if (txSub.endsWith(' PL')) {
      final val = _tryParseDouble(txSub.substring(0, txSub.length - 3));
      r.txSubAudio = val != null ? (val * 100).round() : 0;
    }

    r.scan = false;
    r.txDisable = false;
    r.mute = false;
    r.txAtMaxPower = true;
    r.txAtMedPower = false;
    r.talkAround = false;
    r.preDeEmphBypass = false;

    return r;
  }

  /// Exports channels to native HTCommander CSV format.
  static String exportNative(List<RadioChannelInfo?> channels) {
    final sb = StringBuffer();
    sb.writeln(
        'title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),'
        'rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),'
        'bandwidth(12500/25000),scan(0=OFF/1=ON),'
        'talk around(0=OFF/1=ON),pre_de_emph_bypass(0=OFF/1=ON),'
        'sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),mute(0=OFF/1=ON),'
        'rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)');
    for (final c in channels) {
      if (c == null || c.txFreq == 0 || c.rxFreq == 0) continue;
      String power = 'L';
      if (c.txAtMaxPower) power = 'H';
      if (c.txAtMedPower) power = 'M';
      sb.writeln([
        c.nameStr,
        c.txFreq.toString(),
        c.rxFreq.toString(),
        c.txSubAudio.toString(),
        c.rxSubAudio.toString(),
        power,
        c.bandwidth == RadioBandwidthType.narrow ? '12500' : '25000',
        c.scan ? '1' : '0',
        c.talkAround ? '1' : '0',
        c.preDeEmphBypass ? '1' : '0',
        c.sign ? '1' : '0',
        c.txDisable ? '1' : '0',
        c.mute ? '1' : '0',
        c.rxMod.value.toString(),
        c.txMod.value.toString(),
      ].join(','));
    }
    return sb.toString();
  }

  /// Exports channels to CHIRP CSV format.
  static String exportChirp(List<RadioChannelInfo?> channels) {
    final sb = StringBuffer();
    sb.writeln('Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,'
        'cToneFreq,DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power');
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i];
      if (c == null || c.txFreq == 0 || c.rxFreq == 0) continue;

      String duplex = '';
      if (c.txFreq < c.rxFreq) duplex = '-';
      if (c.txFreq > c.rxFreq) duplex = '+';
      final offset = (c.txFreq - c.rxFreq).abs() / 1000000;

      String tone = '';
      String rToneFreq = '';
      String cToneFreq = '';
      String dtcsCode = '';
      String dtcsPolarity = '';

      if (c.txSubAudio >= 1000 && c.rxSubAudio >= 1000) {
        tone = 'TONE';
        rToneFreq = (c.rxSubAudio / 100).toString();
        cToneFreq = (c.txSubAudio / 100).toString();
      } else if (c.txSubAudio > 0 &&
          c.rxSubAudio > 0 &&
          c.txSubAudio < 1000 &&
          c.rxSubAudio < 1000 &&
          c.rxSubAudio == c.txSubAudio) {
        tone = 'DTCS';
        dtcsCode = c.rxSubAudio.toString();
        dtcsPolarity = 'NN';
      }

      String mode;
      if (c.rxMod == RadioModulationType.fm) {
        mode = c.bandwidth == RadioBandwidthType.wide ? 'FM' : 'NFM';
      } else {
        mode = c.rxMod.name.toUpperCase();
      }

      String power;
      if (c.txAtMaxPower) {
        power = '5.0W';
      } else if (c.txAtMedPower) {
        power = '3.0W';
      } else {
        power = '1.0W';
      }

      sb.writeln([
        i.toString(),
        c.nameStr,
        (c.rxFreq / 1000000).toStringAsFixed(6),
        duplex,
        offset.toStringAsFixed(6),
        tone,
        rToneFreq,
        cToneFreq,
        dtcsCode,
        dtcsPolarity,
        mode,
        '',
        '',
        power,
      ].join(','));
    }
    return sb.toString();
  }

  /// Writes channel data to a file.
  static void writeChannelsToFile(
      List<RadioChannelInfo?> channels, String filename, int format) {
    final content =
        format == 1 ? exportNative(channels) : exportChirp(channels);
    File(filename).writeAsStringSync(content);
  }

  static RadioModulationType _parseModulation(String mod) {
    switch (mod) {
      case 'AM':
        return RadioModulationType.am;
      case 'DMR':
        return RadioModulationType.dmr;
      default:
        return RadioModulationType.fm;
    }
  }

  static String _getValue(
      List<String> parts, Map<String, int> headers, String key) {
    final idx = headers[key];
    if (idx != null && idx < parts.length) return parts[idx].trim();
    return '';
  }

  static String _removeQuotes(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static int? _tryParseInt(String s) {
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  static double? _tryParseDouble(String s) {
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
}
