import 'dart:ffi';
import 'package:ffi/ffi.dart';

// --- Constants ---

/// AF_BLUETOOTH socket domain.
const int afBluetooth = 31;

/// SOCK_STREAM socket type.
const int sockStream = 1;

/// BTPROTO_RFCOMM protocol.
const int btprotoRfcomm = 3;

/// fcntl: get file status flags.
const int fGetfl = 3;

/// fcntl: set file status flags.
const int fSetfl = 4;

/// O_NONBLOCK flag for non-blocking I/O.
const int oNonblock = 0x800;

/// errno: Resource temporarily unavailable (try again).
const int eagain = 11;

/// errno: Interrupted system call.
const int eintr = 4;

/// errno: Connection refused.
const int econnrefused = 111;

/// errno: Host is down.
const int ehostdown = 112;

/// poll() event: there is data to read.
const int pollin = 1;

/// poll() event: error condition.
const int pollerr = 4;

/// poll() event: hang up.
const int pollhup = 8;

/// poll() event: invalid request.
const int pollnval = 16;

// --- Structs ---

/// struct pollfd for poll() syscall.
final class PollFd extends Struct {
  @Int32()
  external int fd;

  @Int16()
  external int events;

  @Int16()
  external int revents;
}

// --- Native function typedefs ---

typedef _SocketNative = Int32 Function(Int32 domain, Int32 type, Int32 protocol);
typedef _SocketDart = int Function(int domain, int type, int protocol);

typedef _ConnectNative = Int32 Function(
    Int32 sockfd, Pointer<Void> addr, Int32 addrlen);
typedef _ConnectDart = int Function(
    int sockfd, Pointer<Void> addr, int addrlen);

typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);

typedef _ReadNative = Int64 Function(
    Int32 fd, Pointer<Void> buf, Int64 count);
typedef _ReadDart = int Function(int fd, Pointer<Void> buf, int count);

typedef _WriteNative = Int64 Function(
    Int32 fd, Pointer<Void> buf, Int64 count);
typedef _WriteDart = int Function(int fd, Pointer<Void> buf, int count);

typedef _Fcntl2Native = Int32 Function(Int32 fd, Int32 cmd);
typedef _Fcntl2Dart = int Function(int fd, int cmd);

typedef _Fcntl3Native = Int32 Function(Int32 fd, Int32 cmd, Int32 arg);
typedef _Fcntl3Dart = int Function(int fd, int cmd, int arg);

typedef _PollNative = Int32 Function(
    Pointer<PollFd> fds, Int32 nfds, Int32 timeout);
typedef _PollDart = int Function(Pointer<PollFd> fds, int nfds, int timeout);

typedef _ErrnoLocationNative = Pointer<Int32> Function();
typedef _ErrnoLocationDart = Pointer<Int32> Function();

/// Native libc bindings for RFCOMM Bluetooth sockets.
class NativeMethods {
  NativeMethods._();

  static final DynamicLibrary _libc = DynamicLibrary.open('libc.so.6');

  static final int Function(int domain, int type, int protocol) socket =
      _libc.lookupFunction<_SocketNative, _SocketDart>('socket');

  static final int Function(int sockfd, Pointer<Void> addr, int addrlen)
      connect =
      _libc.lookupFunction<_ConnectNative, _ConnectDart>('connect');

  static final int Function(int fd) close =
      _libc.lookupFunction<_CloseNative, _CloseDart>('close');

  static final int Function(int fd, Pointer<Void> buf, int count) read =
      _libc.lookupFunction<_ReadNative, _ReadDart>('read');

  static final int Function(int fd, Pointer<Void> buf, int count) write =
      _libc.lookupFunction<_WriteNative, _WriteDart>('write');

  /// fcntl with 2 arguments (e.g., F_GETFL).
  static final int Function(int fd, int cmd) fcntl =
      _libc.lookupFunction<_Fcntl2Native, _Fcntl2Dart>('fcntl');

  /// fcntl with 3 arguments (e.g., F_SETFL).
  static final int Function(int fd, int cmd, int arg) fcntl3 =
      _libc.lookupFunction<_Fcntl3Native, _Fcntl3Dart>('fcntl');

  static final int Function(Pointer<PollFd> fds, int nfds, int timeout) poll =
      _libc.lookupFunction<_PollNative, _PollDart>('poll');

  static final _ErrnoLocationDart _errnoLocation =
      _libc.lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>(
          '__errno_location');

  /// Returns the current errno value.
  static int get errno => _errnoLocation().value;
}

/// Builds a `sockaddr_rc` structure for RFCOMM Bluetooth connection.
///
/// Layout (10 bytes):
/// - [0..1]: sa_family (uint16 LE, AF_BLUETOOTH = 31)
/// - [2..7]: bdaddr (6 bytes, reversed byte order)
/// - [8]:    channel (uint8)
/// - [9]:    padding
///
/// The caller must free the returned pointer with [calloc.free].
Pointer<Uint8> buildSockaddrRc(List<int> bdaddr, int channel) {
  final ptr = calloc<Uint8>(10);
  // sa_family = AF_BLUETOOTH (31) in little-endian
  ptr[0] = afBluetooth & 0xFF;
  ptr[1] = (afBluetooth >> 8) & 0xFF;
  // bdaddr in reversed byte order
  for (int i = 0; i < 6; i++) {
    ptr[2 + i] = bdaddr[5 - i];
  }
  // RFCOMM channel
  ptr[8] = channel;
  // Padding
  ptr[9] = 0;
  return ptr;
}

/// Parses a MAC address string into 6 bytes.
///
/// Accepts "XX:XX:XX:XX:XX:XX" or "XXXXXXXXXXXX" format.
List<int> parseMacAddress(String mac) {
  final clean = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
  if (clean.length != 12) {
    throw ArgumentError('Invalid MAC address: $mac');
  }
  final bytes = <int>[];
  for (int i = 0; i < 6; i++) {
    bytes.add(int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16));
  }
  return bytes;
}
