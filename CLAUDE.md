# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

HTCommander is a ham radio controller for Bluetooth-enabled handhelds (UV-Pro, UV-50Pro, GA-5WB, VR-N75, VR-N76, VR-N7500, VR-N7600, RT-660). **Active development is in the Flutter rewrite** (`htcommander_flutter/`). The C#/Avalonia app in the root is the stable reference implementation.

Two git remotes: `origin` (Ylianst/HTCommander upstream), `fork` (dikei100/HTCommander-X). Push to `fork` with `--tags` to trigger releases.

## C#/Avalonia App (reference, stable)

### Build

**.NET SDK 9.0** required. `dotnet build HTCommander.sln` / `dotnet run --project HTCommander.Desktop/HTCommander.Desktop.csproj`. No test projects. Versioning in `HTCommander.Desktop.csproj` `<Version>` property — must match git tag.

### Architecture

```
HTCommander.Desktop (Avalonia UI) ──┐
                                     ├──> HTCommander.Core (all business logic)
HTCommander.Platform.Linux ──────────┤
HTCommander.Platform.Windows ────────┘
```

**Core** (net9.0): Radio.cs (GAIA protocol), DataBroker pub/sub, AX.25/APRS, SBC codec, SSTV, VoiceHandler, RadioAudioManager, servers (MCP/Web/Rigctld/AGWPE/SMTP/IMAP), AudioClipHandler, RepeaterBookClient, AdifExport.

**Key patterns**: DataBroker event flow (device 0=settings, 1=app events, 100+=radios), data handler self-registration, radio connection lifecycle (transport→OnConnected→GAIA init→DataBroker dispatch), IRadioHost interface for circular dependency breaking.

**Linux Bluetooth**: Direct native RFCOMM sockets. `poll()`/`SO_RCVTIMEO` broken on RFCOMM — use `O_NONBLOCK` + `Thread.Sleep(50)`. `OnConnected` must fire on background thread. RFCOMM channels vary by model (VR-N76: ch 1 or 4 for commands, ch 2 for audio). Block SIGPROF around syscalls.

### GAIA Protocol

```
[0xFF] [0x01] [flags] [body_length] [group_hi] [group_lo] [cmd_hi] [cmd_lo] [body...]
```
- `body_length` = cmd body only (max 255), total frame = body_length + 8
- Reply bit: `cmd_hi | 0x80`. Frequencies stored in Hz.
- SBC codec: 32kHz, 16 blocks, mono, loudness allocation, 8 subbands, bitpool 18
- Audio framing: `0x7E` start/end, `0x7D` escape (XOR `0x20`). Separate RFCOMM channel (GenericAudio UUID `00001203`).

### Code Conventions

- net9.0, nullable disabled, implicit usings disabled, unsafe blocks enabled
- Radio state dispatched as **string** (e.g. `"Connected"`)
- Settings: int 0/1 for booleans, `DataBroker.GetValue<int>(0, key, 0) == 1`
- Avalonia: `ComboBox` has no `.Text` — use `AutoCompleteBox`. Dialogs use `Confirmed` bool pattern.
- SSTV uses SkiaSharp, not System.Drawing

### Security Summary

All servers default to loopback. MCP requires Bearer token when `ServerBindAll` enabled. All subprocess calls use `ArgumentList` (no injection). Path traversal validated via `GetFullPath()` prefix check. Protocol bounds checked on all constructors. Error responses never expose `ex.Message`. Files chmod 600 on Linux. CSP on web pages. Constant-time auth comparisons throughout.

---

## HTCommander-X Flutter Rewrite (`htcommander_flutter/`)

Full Dart/Flutter rewrite targeting Linux desktop, Windows, and Android. Uses "Signal Protocol" design system (dark base `#0c0e17`, cyan primary `#3cd7ff`, glassmorphism, Inter font). Stitch project "HTCommander-X: New UI" is the design reference. ~150 source files, ~40K LOC, 180 tests.

### Prerequisites

**Flutter SDK** (stable, v3.41.5+) at `~/flutter`. Add to PATH: `export PATH="$HOME/flutter/bin:$PATH"`. Linux: `sudo pacman -S ninja gcc`.

### Build Commands

```bash
cd htcommander_flutter
~/flutter/bin/flutter pub get
~/flutter/bin/flutter analyze        # must pass with zero errors (warnings OK for unused protocol fields)
~/flutter/bin/flutter test           # 180 tests
~/flutter/bin/flutter test test/handlers/  # run a specific test directory
~/flutter/bin/flutter test test/radio/gps_test.dart  # run a single test file
~/flutter/bin/flutter analyze lib/handlers/aprs_handler.dart  # analyze a single file
~/flutter/bin/flutter run -d linux
~/flutter/bin/flutter build linux --release  # → build/linux/x64/release/bundle/htcommander-x
~/flutter/bin/flutter build apk
```

Note: Flutter SDK is at `~/flutter/bin/flutter` (not on PATH by default).

### Architecture

**Startup**: `WidgetsFlutterBinding.ensureInitialized()` → `SharedPrefsSettingsStore.create()` → `DataBroker.initialize(store)` → `initializeDataHandlers()` → `runApp()`.

**App shell** (`app.dart`): Holds `Radio?` and `PlatformServices?`. No top toolbar — sidebar contains branding, frequency display, callsign, and connect/disconnect. Screens in `IndexedStack` (preserves state across tab switches). Sidebar has 8 nav items (Communication, Contacts, Packets, Terminal, BBS, Mail, Torrent, APRS); Logbook/Map/Debug remain in IndexedStack but not in sidebar nav. `_sidebarToScreen` maps sidebar indices to screen indices. MCP `McpConnectRadio`/`McpDisconnectRadio` events wired for remote control.

**Key directories**:
- `core/` — DataBroker pub/sub, DataBrokerClient, SharedPreferences SettingsStore
- `radio/` — GAIA state machine (76 basic + 6 extended commands), SBC codec, morse/DTMF
- `radio/modem/` — Software packet modem: DSP, AFSK 1200, 9600 G3RUH, PSK, HDLC, FX.25 (Reed-Solomon FEC), MultiModem
- `radio/sstv/` — SSTV encoder/decoder (20+ modes: Robot, Scottie, Martin, Wraase, PD, HF Fax), SstvMonitor, FFT, DSP
- `radio/ax25/` — AX.25 packet/address/session
- `radio/aprs/` — APRS packet parser, position, message, weather
- `radio/gps/` — NMEA 0183 parser (GGA, RMC, GSA, GSV, VTG, GLL, ZDA), GPS data model
- `handlers/` — 18 DataBroker handlers (FrameDeduplicator, PacketStore, AprsHandler, LogStore, MailStore, VoiceHandler, AudioClipHandler, TorrentHandler, BbsHandler, WinlinkClient, YappTransfer, RepeaterBookClient, ImportUtils, AdifExport, GpsSerialHandler, AirplaneHandler, server stubs on mobile)
- `handlers/adventurer/` — Text adventure game (Easter egg)
- `dialogs/` — 31 dialog widgets (APRS, radio config, channel editor, SSTV send, spectrogram, RepeaterBook, mail, etc.)
- `servers/` — MCP (real on desktop, 16 tools), Web, Rigctld, AGWPE, SMTP, IMAP, CAT Serial (TS-2000)
- `platform/linux/` — dart:ffi RFCOMM Bluetooth (Isolate), audio I/O (paplay/parecord)
- `screens/` — 12 screens wired to DataBroker. Communication screen loads current state on init. Screens use 42px inline header bars (not 46px).
- `widgets/` — VfoDisplay, PttButton, SignalBars, RadioStatusCard, GlassCard, SidebarNav, StatusStrip

### DataBroker Pattern (Same as C#)

`DataBroker.dispatch(deviceId, name, data)` / `broker.subscribe(deviceId, name, callback)`. Device 0 = settings (auto-persisted), device 1 = app events, device 100+ = radios. Screens subscribe in `initState()`, call `setState()` in callbacks. Handlers self-initialize in constructors.

### Linux Bluetooth (dart:ffi)

`native_methods.dart` binds libc: `socket()`, `connect()`, `close()`, `read()`, `write()`, `fcntl()`, `poll()`, `sigprocmask()`, `sigemptyset()`, `sigaddset()`. Poll constants: POLLIN=1, POLLOUT=4, POLLERR=8, POLLHUP=16, POLLNVAL=32.

Connection flow: `bluetoothctl connect` (ACL, 3s wait) → `sdptool browse` (SDP) → RFCOMM socket per channel → GAIA GET_DEV_ID verification → async read loop. Channel probing: 1-30.

**Critical**: Read loop MUST be `async` with `await Future.delayed()`, NOT `sleep()`. Dart isolates are single-threaded — `sleep()` blocks the event loop, preventing write command delivery. Writes queued in `List<Uint8List>`, drained by read loop between reads. SIGPROF/SIGALRM blocked around each syscall batch and restored before yielding.

**Disconnect**: Sends `{'cmd': 'disconnect'}` then delays 1s before killing isolate for clean fd close. Without this, fd leaks and reconnection fails (ECONNREFUSED on all channels).

**Connection loss**: When `Radio._onReceivedData` gets error+null, calls `disconnect()` to transition state. Read loop logs exit reason before exiting.

### Audio Pipeline (Fully Wired)

**RX**: BT audio RFCOMM → 0x7E deframe → SBC decode → PCM → `LinuxAudioOutput` → `paplay` (mono→stereo). **TX**: PTT press → `LinuxMicCapture` → `parecord` (48kHz) → resample to 32kHz → `TransmitVoicePCM` event → `RadioAudioManager` → SBC encode → 0x7E frame → BT audio RFCOMM. PTT release → `CancelVoiceTransmit` event → end frame sent.

**Lifecycle**: `Radio` creates `RadioAudioManager` in constructor, subscribes to `SetAudio` event. Audio auto-starts 3s after radio connects via `_setAudioEnabled(true)`. `LinuxMicCapture`/`LinuxAudioOutput` are instantiated by `CommunicationScreen` on PTT press / `AudioState(true)` respectively.

### Dialog Pattern

Dialogs in `lib/dialogs/` follow Signal Protocol design system. Key conventions:
- `Dialog` with `surfaceContainerHigh` background, `BorderRadius.circular(8)`
- 9px uppercase bold headers (`letterSpacing: 1, fontWeight: w700`)
- 10-11px body text, `outlineVariant` borders, compact `InputDecoration`
- Return results via `Navigator.pop(context, result)`, null on cancel
- Stateless for read-only display, StatefulWidget for forms with controllers

### Handler Initialization

Some handlers require `initialize(appDataPath)` after construction for file persistence (PacketStore, VoiceHandler, BbsHandler, TorrentHandler, WinlinkClient). Called from `initializeDataHandlers()` in `main.dart` after app data directory is resolved.

### Conventions

- Import `radio/radio.dart` with `as ht` prefix (avoids Flutter `Radio` widget clash)
- Dart `int` is 64-bit — use `& 0xFFFFFFFF` for unsigned 32-bit
- C# `byte[]` → `Uint8List`, `short[]` → `Int16List`
- C# `SynchronizationContext.Post()` → `Future.microtask()`
- C# `volatile`/`lock` → Dart main isolate is single-threaded; use `Completer` for async
- C# `Thread` → Dart `Isolate` (RFCOMM) or `async`/`await`
- Settings: int 0/1 for booleans: `DataBroker.getValue<int>(0, key, 0) == 1`

## Repository Structure

- `HTCommander.Core/`, `HTCommander.Platform.Linux/`, `HTCommander.Platform.Windows/`, `HTCommander.Desktop/` — C#/Avalonia app
- `htcommander_flutter/` — Flutter rewrite (active development)
- `docs/` — architecture docs
- `packaging/linux/` — AppImage/deb build scripts
- `web/` — embedded web interface (desktop Web Bluetooth + mobile SPA)
- `assets/` — shared icons
- `.github/workflows/release.yml` — CI/CD (version tags trigger builds)

## Related Projects

- [khusmann/benlink](https://github.com/khusmann/benlink) — Python GAIA protocol reference
- [SarahRoseLives/flutter_benlink](https://github.com/SarahRoseLives/flutter_benlink) — Dart GAIA reference, VR-N76 quirks
