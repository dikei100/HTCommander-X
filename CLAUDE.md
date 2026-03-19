# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build individual projects
dotnet build HTCommander.Core/HTCommander.Core.csproj
dotnet build HTCommander.Platform.Linux/HTCommander.Platform.Linux.csproj
dotnet build HTCommander.Desktop/HTCommander.Desktop.csproj

# Build original WinForms project (requires Windows or cross-compile flag)
dotnet build src/HTCommander.csproj -p:EnableWindowsTargeting=true

# Run the Avalonia Desktop app (Linux)
dotnet run --project HTCommander.Desktop/HTCommander.Desktop.csproj

# Linux packaging
./packaging/linux/build-appimage.sh Release
./packaging/linux/build-deb.sh Release
```

No test projects exist in this codebase.

## Architecture

HTCommander is a ham radio controller for Bluetooth-enabled handhelds (UV-PRO, VR-N75, VR-N76, VR-N7500, etc.). It was migrated from a monolithic WinForms app to a multi-project cross-platform architecture.

### Project Dependency Graph

```
HTCommander.Desktop (Avalonia UI) ──┐
                                     ├──> HTCommander.Core (all business logic)
HTCommander.Platform.Linux ──────────┤
HTCommander.Platform.Windows ────────┘
src/ (original WinForms) ────────────┘
```

### HTCommander.Core (net9.0) — 154 files, zero UI dependencies

All radio protocol logic, data handlers, codecs, and parsers. Key subsystems:
- **Radio.cs**: GAIA protocol over Bluetooth RFCOMM — the central class managing radio connections, commands, channels, GPS
- **DataBroker / DataBrokerClient**: Global pub/sub event bus. Device-scoped data channels with optional persistence via `ISettingsStore`. Uses `SynchronizationContext.Post()` for UI thread marshalling (not WinForms `Control.BeginInvoke`)
- **Interfaces/**: Platform abstractions (`IPlatformServices`, `IRadioBluetooth`, `IAudioService`, `ISpeechService`, `ISettingsStore`, `IFilePickerService`, `IPlatformUtils`, `IRadioHost`, `IWhisperEngine`)
- **radio/**: AX.25 packet protocol, SoftwareModem (DSP), GAIA frame encode/decode
- **SSTV/**: Slow-scan TV image encode/decode using SkiaSharp (not System.Drawing)
- **VoiceHandler**: Speech processing — takes `ISpeechService` constructor param, uses `VoiceHandler.WhisperEngineFactory` static delegate for STT

### Platform Projects

**Platform.Windows** (net9.0-windows): WinRT Bluetooth, NAudio/WASAPI audio, System.Speech TTS, Windows Registry settings

**Platform.Linux** (net9.0): BlueZ D-Bus Bluetooth (ProfileManager1 API with native RFCOMM sockets), PortAudio audio, espeak-ng TTS, JSON file settings at `~/.config/HTCommander/`

### HTCommander.Desktop (net9.0) — Avalonia UI

10 tab controls + 39 dialogs + Mapsui map. Platform auto-detected at startup via reflection in `Program.cs`. Conditional project references load Windows or Linux platform assembly.

### src/ (net9.0-windows) — Original WinForms app

Still builds and runs on Windows. References Core. Files moved to Core are excluded via `<Compile Remove>` in the csproj. Contains Windows-only code: RadioAudio.cs (NAudio+WinRT), Microphone.cs, WhisperEngine.cs, AirplaneMarker.cs (GMap.NET), and WinForms UI (Dialogs/, TabControls/, Controls/).

## Key Patterns

### DataBroker event flow
Components communicate via `DataBroker.Dispatch(deviceId, name, data)` and `broker.Subscribe(deviceId, name, callback)`. Device 0 = global settings (persisted to ISettingsStore). Device 1 = app-level events. Device 100+ = connected radios. All UI callbacks are marshalled via `SynchronizationContext`.

### Radio connection lifecycle
1. `IPlatformServices.CreateRadioBluetooth(IRadioHost)` creates transport
2. `Radio.Connect()` → `IRadioBluetooth.Connect()` → async BT connection
3. Transport fires `OnConnected` → Radio sends GAIA GET_DEV_INFO, READ_SETTINGS, etc.
4. Transport fires `ReceivedData(Exception, byte[])` → Radio processes GAIA responses
5. Radio dispatches state/data to DataBroker → UI tabs update via subscriptions

### IRadioHost interface
Breaks circular dependency: platform BT transports need `Radio.Debug()` and `Radio.Disconnect()` but can't reference Radio directly. `IRadioHost` in Core defines `MacAddress`, `Debug(string)`, `Disconnect(string, RadioState)`. Radio implements it.

### Linux Bluetooth (BlueZ ProfileManager1)
Registers SPP profile via D-Bus → calls `ConnectProfile(SPP_UUID)` → receives fd in `NewConnection` callback → **must `dup()` the fd** before callback returns (Tmds.DBus closes the original) → uses native `read()`/`write()` P/Invoke. Known issue: fd obtained and validated but radio not responding to GAIA commands.

## Code Conventions

- **Target**: net9.0 (Core, Linux, Desktop), net9.0-windows (WinForms, Platform.Windows)
- **Nullable**: disabled across all projects
- **ImplicitUsings**: disabled — all usings are explicit
- **AllowUnsafeBlocks**: enabled (SBC codec, SkiaSharp pixel ops, native P/Invoke)
- **Namespace**: `HTCommander` for Core and src/, `HTCommander.Platform.Linux`, `HTCommander.Platform.Windows`, `HTCommander.Desktop` for other projects
- Radio dispatches state as **string** (e.g., `"Connected"`, not the enum), so subscribers must compare strings
- `Utils` is a **partial class** — cross-platform methods in Core, WinForms-specific (SetDoubleBuffered, SendMessage) in src/
- Avalonia dialogs use `Confirmed` bool property pattern for OK/Cancel results
- SSTV imaging uses SkiaSharp (`SKBitmap`), not System.Drawing. WinForms bridge: `SkiaBitmapConverter`

## Repository Structure

- `docs/CrossPlatformArchitecture.md` — detailed architecture documentation with design decision rationale
- `packaging/linux/` — AppImage and .deb build scripts
- `HTCommander.setup/` — Windows MSI installer project
- Two git remotes: `origin` (Ylianst/HTCommander upstream), `fork` (dikei100/HTCommander)
- Active branch: `cross-platform`
