import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander_flutter/handlers/packet_store.dart';

void main() {
  group('PacketStore.parsePacketLine', () {
    test('parses TncFrag format', () {
      // C# ticks for ~2026-01-15 12:00:00 UTC
      const ticks = 638747520000000000;
      final line = '$ticks,1,TncFrag,5,48454C4C4F';
      final packet = PacketStore.parsePacketLine(line);
      expect(packet, isNotNull);
      expect(packet!.incoming, isTrue);
      expect(packet.channelId, equals(5));
    });

    test('parses TncFrag2 format with channel name', () {
      const ticks = 638747520000000000;
      final line = '$ticks,0,TncFrag2,3,100,CH3,DEADBEEF';
      final packet = PacketStore.parsePacketLine(line);
      expect(packet, isNotNull);
      expect(packet!.incoming, isFalse);
      expect(packet.channelId, equals(3));
      expect(packet.channelName, equals('CH3'));
    });

    test('parses TncFrag3 format', () {
      const ticks = 638747520000000000;
      final line = '$ticks,1,TncFrag3,2,100,CH2,FF00FF,3,1,0';
      final packet = PacketStore.parsePacketLine(line);
      expect(packet, isNotNull);
      expect(packet!.incoming, isTrue);
    });

    test('parses TncFrag4 format', () {
      const ticks = 638747520000000000;
      final line = '$ticks,1,TncFrag4,2,100,CH2,FF00FF,3,1,2,AA:BB:CC:DD';
      final packet = PacketStore.parsePacketLine(line);
      expect(packet, isNotNull);
    });

    test('returns null for invalid format', () {
      expect(PacketStore.parsePacketLine('invalid'), isNull);
      expect(PacketStore.parsePacketLine('1,2'), isNull);
      expect(PacketStore.parsePacketLine('abc,1,TncFrag,5,FF'), isNull);
    });

    test('returns null for unknown fragment type', () {
      const ticks = 638747520000000000;
      expect(PacketStore.parsePacketLine('$ticks,1,Unknown,5,FF'), isNull);
    });
  });

  group('PacketStore.hexDump', () {
    test('formats short data correctly', () {
      final data =
          Uint8List.fromList([0x48, 0x45, 0x4C, 0x4C, 0x4F]); // HELLO
      final dump = PacketStore.hexDump(data);
      expect(dump, contains('0000'));
      expect(dump, contains('48 45 4c 4c 4f'));
      expect(dump, contains('HELLO'));
    });

    test('formats data with non-printable bytes', () {
      final data = Uint8List.fromList([0x00, 0x01, 0x7F, 0x41]);
      final dump = PacketStore.hexDump(data);
      expect(dump, contains('..'));
      expect(dump, contains('A'));
    });

    test('handles 16+ byte rows', () {
      final data = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        data[i] = i;
      }
      final dump = PacketStore.hexDump(data);
      expect(dump, contains('0000'));
      expect(dump, contains('0010'));
    });

    test('handles empty data', () {
      final dump = PacketStore.hexDump(Uint8List(0));
      expect(dump, isEmpty);
    });
  });
}
