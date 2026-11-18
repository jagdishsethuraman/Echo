# AGENTS.md — Echo

Echo is a native macOS (14+) menu-bar app: push-to-talk dictation, live
transcription via the local Phonon STT engine, and bot-free meeting capture.
Swift 6 toolchain, SwiftPM package (`swiftLanguageModes: [.v5]` — do not
introduce Swift 6 language mode features).

## Xcode integration

Xcode 27 exposes its tools over MCP; this repo is usually open as a window tab.

- Call `XcodeListWorkspaces` first and pick the entry whose `workspacePath` is
  `/Users/ragavij/Documents/Developer/Echo`. Workspace ids change between Xcode
  launches, and absolute paths are not accepted as `workspaceIdentifier`.
- Scheme: `Echo`. Destination: `My Mac` (arm64, macOS 27.2 SDK).
- Prefer Xcode tools over raw shell builds: `BuildProject`, `RunAllTests`,
  `RunSomeTests`, `GetBuildLog`, `RenderPreview`, `XcodeRead`/`XcodeWrite`/`XcodeGrep`.
- `XcodeListTargets` returns empty for this SwiftPM package — use scheme-level
  tools instead.

## Build & test

```sh
swift build
swift test                     # 63 Swift Testing tests
```

Debug builds can render the main surfaces without screen-recording
permission:

```sh
.build/debug/Echo --snapshot /tmp/echo-ui
```

If only Command Line Tools are selected (no Xcode), add:

```sh
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
```

## Layout

- `Sources/Echo/Audio/` — CoreAudio tap, ScreenCaptureKit loopback, VAD, WAV encoder
- `Sources/Echo/Engine/` — Phonon process runner, STT types, MeetingCoordinator
- `Sources/Echo/Injection/` — TextInjector, SystemEventPoster, HotkeyManager
- `Sources/Echo/Storage/` — SQLite `DatabaseManager`, `WordMemoryEngine`, models
- `Sources/Echo/UI/` — floating HUD pill, MenuBarManager, DesignSystem,
  `MeetingStudio/` Bento views
- `Tests/EchoTests/` — unit tests; `test_samples/` holds 16 kHz reference audio

## Conventions

- Never edit `project.pbxproj` or generated build products; use SwiftPM sources.
- Keep everything local — no network calls, no cloud APIs.
- `ARCHITECTURE.md`, `CODE_REVIEW.md`, `ROADMAP.md` and `CHANGELOG.md` describe
  intent and known debt; read them before large refactors and update
  `CHANGELOG.md` when behavior changes.
- Audio paths assume 16 kHz mono Int16 PCM; converters own resampling.
