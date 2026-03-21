---
name: merge-upstream
description: Fetch, analyze, and merge new commits from the upstream Ylianst/HTCommander repo into our cross-platform fork, mapping files to the correct project locations.
user_invocable: true
---

# Merge Upstream

Merge new commits from the upstream `origin` remote (Ylianst/HTCommander) into our cross-platform fork. The legacy `src/` WinForms project has been removed — all upstream changes must be mapped to the cross-platform project structure.

## Step 1: Fetch & Identify New Commits

```bash
git fetch origin
git log --oneline origin/main --not HEAD
```

If there are no new commits, tell the user and stop.

## Step 2: Analyze Each Commit

For each new upstream commit, run `git show --stat <hash>` and `git show <hash>` to see the full diff. Categorize every changed file using the mapping table below.

### File Mapping Table

| Upstream `src/` path | Our target location | Action |
|---|---|---|
| `src/radio/**` | `HTCommander.Core/radio/` | Direct merge |
| `src/Utils/(DataBroker,AprsHandler,BbsHandler,MailStore,PacketStore,LogStore,AgwpeServer,SmtpServer,ImapServer,VoiceHandler,SoftwareModem,FrameDeduplicator,AudioClipHandler,GpsSerialHandler,Torrent,WinlinkClient).cs` | `HTCommander.Core/Utils/` | Direct merge |
| `src/adventurer/**` | `HTCommander.Core/adventurer/` | Direct merge |
| `src/AprsParser/**` | `HTCommander.Core/AprsParser/` | Direct merge |
| `src/hamlib/**` | `HTCommander.Core/hamlib/` | Direct merge |
| `src/sbc/**` | `HTCommander.Core/sbc/` | Direct merge |
| `src/WinLink/**` | `HTCommander.Core/WinLink/` | Direct merge |
| `src/Gps/**` | `HTCommander.Core/Gps/` | Direct merge |
| `src/SSTV/**` | `HTCommander.Core/SSTV/` | **Watch for System.Drawing → SkiaSharp conflicts** |
| `src/Airplanes/(Aircraft,AirplaneHandler,SbsDecoder).cs` | `HTCommander.Core/Airplanes/` | Direct merge |
| `src/Airplanes/AirplaneMarker.cs` | Skip | GMap.NET/WinForms dependency, no longer maintained |
| `src/ChannelImport.cs` | `HTCommander.Core/` | Direct merge |
| `src/StationInfoClass.cs` | `HTCommander.Core/` | Direct merge |
| `src/Yapp.cs` | `HTCommander.Core/` | Direct merge |
| `src/Controls/**`, `src/Dialogs/**`, `src/TabControls/**`, `src/RadioControls/**`, `src/MainForm*` | Avalonia equivalents in `HTCommander.Desktop/` | Assess for Avalonia adaptation |
| `src/BBS.cs`, `src/AprsStack.cs` | Assess | Check if Core has equivalent logic |
| `src/RadioAudio.cs`, `src/Microphone.cs`, `src/WhisperEngine.cs` | Check `Platform.Windows` | Platform-specific |
| `HTCommander.setup/**`, `*.vdproj`, `Updater/**` | Skip | Removed from project |
| `src/Properties/**`, `src/*.resx` | Skip | WinForms resources, no longer maintained |
| Root files (`README.md`, `.gitignore`, etc.) | Evaluate case-by-case | May need merge or skip |

### Category Summary

Group the changes into these categories for the user:
- **Core logic** — changes that map directly to `HTCommander.Core/`
- **UI changes** — WinForms UI changes that may need Avalonia equivalents in `HTCommander.Desktop/`
- **Platform-specific** — may affect Platform.Windows or Platform.Linux
- **Skip** — installer metadata, WinForms resources, removed components
- **SSTV/Image** — needs special attention for System.Drawing vs SkiaSharp

## Step 3: Present Summary & Get Confirmation

Show the user a clear summary:

```
## Upstream Changes Summary

**X new commits** from origin/main

### Core logic (auto-merge)
- file1.cs — description of change
- file2.cs — description of change

### UI changes (needs Avalonia adaptation)
- Dialog1.cs — description of change
  → Avalonia equivalent: HTCommander.Desktop/Dialogs/Dialog1Dialog.axaml.cs

### Skip
- HTCommander.setup/... — removed from project
- src/Properties/... — WinForms resources

Shall I proceed?
```

Wait for user confirmation before applying changes.

## Step 4: Apply Changes

For each category:

1. **Core logic**: Read the upstream diff, apply the same changes to the `HTCommander.Core/` file. If the file doesn't exist in Core yet, determine where it belongs using the mapping table.

2. **UI changes**: For each UI change, check if there's an Avalonia equivalent in `HTCommander.Desktop/`. If so, ask the user whether to adapt the change.

3. **Platform-specific**: Check if `Platform.Windows` or `Platform.Linux` have equivalent code that needs updating.

4. **SSTV/Image**: If the upstream change uses `System.Drawing` (Bitmap, Graphics, Color, etc.), adapt it to use SkiaSharp (`SKBitmap`, `SKCanvas`, `SKColor`, etc.) for the Core version.

### Important: Merge origin/main

After applying all changes, merge `origin/main` into our branch so GitHub shows we're up to date:

```bash
git merge origin/main --no-edit
```

If there are merge conflicts, resolve them according to the file mapping rules above. Our cross-platform versions in `HTCommander.Core/` and `HTCommander.Desktop/` take precedence for files that have been migrated.

## Step 5: Build Verification

Run the build and fix any errors:

```bash
dotnet build HTCommander.Core/HTCommander.Core.csproj
dotnet build HTCommander.Desktop/HTCommander.Desktop.csproj
```

## Step 6: Verify Fully Merged

```bash
git log --oneline origin/main --not HEAD
```

This should return empty, confirming all upstream commits are merged.

## Step 7: Commit

If there are uncommitted changes from manual adaptations (beyond what the merge commit covers), create a descriptive commit explaining what was adapted for cross-platform compatibility.

## Special Cases

- **New files upstream**: If upstream adds a new `.cs` file under `src/`, determine where it belongs using the mapping table. Add it to the appropriate project (`HTCommander.Core/` for logic, `HTCommander.Desktop/` for UI).
- **Deleted files upstream**: Check if the file exists in `HTCommander.Core/` — if so, it may need to be deleted there too.
- **Namespace changes**: Core files use `namespace HTCommander`, same as the original `src/`. No namespace remapping needed.
- **New NuGet dependencies**: If upstream adds a package reference, add it to the appropriate `.csproj` (Core, Desktop, or platform project).
