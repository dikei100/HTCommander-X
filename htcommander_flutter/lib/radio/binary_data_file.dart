/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Structured binary record file I/O.
/// Port of HTCommander.Core/Utils/BinaryDataFile.cs
///
/// Records are stored as:
///   [recordSize:4] [userType:4] [dataType:4] [data:variable]
/// where dataType is 1=int, 2=string(UTF-8), 3=byte array.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class BinaryDataFile {
  final String _filePath;
  RandomAccessFile? _file;
  bool _isOpened = false;

  // Data type constants
  static const int _dataTypeInt = 1;
  static const int _dataTypeString = 2;
  static const int _dataTypeByteArray = 3;

  BinaryDataFile(this._filePath);

  /// Opens the binary file for reading and writing.
  void open() {
    if (!_isOpened) {
      final file = File(_filePath);
      _file = file.openSync(mode: FileMode.append);
      _isOpened = true;
    }
  }

  /// Closes the binary file and releases resources.
  void close() {
    if (_isOpened) {
      _file?.closeSync();
      _file = null;
      _isOpened = false;
    }
  }

  /// Sets the file position to the beginning.
  void seekToBegin() {
    if (_isOpened && _file != null) {
      _file!.setPositionSync(0);
    }
  }

  /// Sets the file position to the end.
  void seekToEnd() {
    if (_isOpened && _file != null) {
      _file!.setPositionSync(_file!.lengthSync());
    }
  }

  /// Appends a record. [data] can be [int], [String], or [Uint8List].
  void appendRecord(int userType, Object data) {
    if (!_isOpened || _file == null) {
      throw StateError('File must be opened before appending a record.');
    }

    int dataType;
    Uint8List dataBytes;

    if (data is int) {
      dataType = _dataTypeInt;
      dataBytes = Uint8List(4);
      ByteData.view(dataBytes.buffer).setInt32(0, data, Endian.little);
    } else if (data is String) {
      dataType = _dataTypeString;
      dataBytes = Uint8List.fromList(utf8.encode(data));
    } else if (data is Uint8List) {
      dataType = _dataTypeByteArray;
      dataBytes = data;
    } else {
      throw ArgumentError(
          'Unsupported data type. Must be int, String, or Uint8List.');
    }

    // recordSize = 3 ints (12 bytes header) + data length
    final recordSize = 12 + dataBytes.length;
    final header = Uint8List(12);
    final bd = ByteData.view(header.buffer);
    bd.setInt32(0, recordSize, Endian.little);
    bd.setInt32(4, userType, Endian.little);
    bd.setInt32(8, dataType, Endian.little);

    // Seek to end before writing
    _file!.setPositionSync(_file!.lengthSync());
    _file!.writeFromSync(header);
    _file!.writeFromSync(dataBytes);
  }

  /// Reads the next record from the file.
  /// Returns a record with [userType] and [data], or null at end of file.
  /// [data] will be [int], [String], or [Uint8List].
  ({int userType, Object data})? readNextRecord() {
    if (!_isOpened || _file == null) {
      throw StateError('File must be opened before reading a record.');
    }

    if (_file!.positionSync() >= _file!.lengthSync()) {
      return null; // End of file
    }

    final header = _file!.readSync(12);
    if (header.length < 12) return null;

    final bd = ByteData.view(Uint8List.fromList(header).buffer);
    final recordSize = bd.getInt32(0, Endian.little);
    final userType = bd.getInt32(4, Endian.little);
    final dataType = bd.getInt32(8, Endian.little);
    final dataLength = recordSize - 12;

    Object data;
    switch (dataType) {
      case _dataTypeInt:
        final bytes = _file!.readSync(4);
        data =
            ByteData.view(Uint8List.fromList(bytes).buffer)
                .getInt32(0, Endian.little);
        break;
      case _dataTypeString:
        final bytes = _file!.readSync(dataLength);
        data = utf8.decode(bytes);
        break;
      case _dataTypeByteArray:
        data = Uint8List.fromList(_file!.readSync(dataLength));
        break;
      default:
        // Skip unknown data type
        _file!.setPositionSync(_file!.positionSync() + dataLength);
        throw FormatException('Unknown data type: $dataType');
    }

    return (userType: userType, data: data);
  }
}
