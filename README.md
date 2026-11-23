# Echo — Speech Intelligence for macOS

<div align="center">

![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia)-black?style=for-the-badge&logo=apple)
![Hardware](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange?style=for-the-badge&logo=apple)
![Language](https://img.shields.io/badge/Language-Swift%205.10%20%2F%206.0-F05138?style=for-the-badge&logo=swift)
![STT Engine](https://img.shields.io/badge/Engine-Phonon--2%20(158%20MB%20INT6)-purple?style=for-the-badge)
![Storage](https://img.shields.io/badge/Database-SQLite%20(WAL%20Mode)-003B57?style=for-the-badge&logo=sqlite)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

<p align="center">
  <b>Unified push-to-talk cursor dictation, live streaming transcription, and bot-free dual-channel meeting intelligence.</b><br>
  Runs 100% locally and privately on Apple Silicon with <b>zero cloud dependencies</b>.
</p>

[Quick Start](#-quick-start) • [Core Capabilities](#-core-capabilities) • [Keyboard Shortcuts](#-keyboard-shortcuts) • [Architecture](#-architecture) • [Developer Guide](#-developer-guide) • [Roadmap](ROADMAP.md) • [Changelog](CHANGELOG.md)

</div>

---

## 🦌 What is Echo?

**Echo** unites two essential speech intelligence workflows into a single native binary:

1. **Handy-Style Quick Dictation:** Hold `⌃ Control` anywhere on your Mac (or double-tap `⌃` for hands-free lock mode). Recognized words stream live into a floating bottom-center HUD. When released (or tapped again), finalized, sentence-capitalized text is automatically typed or pasted into your active cursor in any app.
2. **Meetily-Style Meeting Studio:** Record meetings without inviting bots or installing virtual audio drivers. Echo captures your microphone via CoreAudio and system attendee audio via `ScreenCaptureKit` loopback, slicing utterances with rolling VAD and generating structured Markdown notes.
3. **Local SQLite & Word Memory:** Every session and dictation is archived in local SQLite (`echo.sqlite`). Writes happen off the main thread, the schema migrates itself, and empty sessions are pruned at launch. A built-in lexicon engine learns personal vocabulary, project jargon, and acronyms, automatically correcting phonetically misheard terms in real time. The menu's **Meeting History** submenu lists recent sessions with copy and delete actions.

---

## ⚡ Quick Start

### 1. Build & Assemble from Source
Clone the repository and run the automated assembly script:
```bash
git clone https://github.com/jagdishsethuraman/Echo.git
cd Echo
./assemble_app.sh
open Echo.app
```
*(Or build via SwiftPM: `swift build -c release`).*

### 2. Speech Engine Setup (Phonon-2 / Fermion)
Echo uses the local Fermion CLI and Phonon-2 model. On Apple Silicon, create a dedicated Python 3.12 environment (install Python first with `brew install python@3.12` if needed). Run from the cloned repository:

```bash
engine="$HOME/Library/Application Support/Echo/engine"
python3.12 -m venv "$engine"
"$engine/bin/python" -m pip install fermion-research mlx mlx-audio mlx-lm soundfile scipy zstandard
defaults write com.ragavij.echo echo.fermionPath "$engine/bin/fermion"
defaults write com.ragavij.echo echo.fermionDevice mlx
"$engine/bin/fermion" transcribe phonon-2 test_samples/short_sample_16k.wav
./Echo.app/Contents/MacOS/Echo --test --verify-speech test_samples/short_sample_16k.wav
```

The first transcription downloads the model. Run it before starting a meeting. The second command verifies a nonempty transcript through Echo's own runner. For a different engine location use its absolute executable path in the same preference. [Fermion speech installation guide](https://www.fermionresearch.com/docs/speech/)

### 3. Grant macOS Permissions
Echo requires standard macOS privacy permissions:
1. **Accessibility:** Open **System Settings → Privacy & Security → Accessibility**, add **Echo**, and toggle it **ON**.
   The assembly script signs ad hoc. macOS may ask you to grant permission again after replacing the app.
2. **Microphone:** Allow microphone access when prompted (or in **Privacy & Security → Microphone**).
3. **Screen & System Audio Recording:** Required for bot-free attendee capture in Meeting Studio (**Privacy & Security → Screen & System Audio Recording**).

### 4. Start Dictating
- Press and hold **`⌃ Control`** in any application (Notion, Slack, Chrome, VS Code, Notes, TextEdit, Terminal).
- **Hands-Free Lock Mode:** Double-tap **`⌃ Control`** rapidly to lock recording on (displays `🔒 LOCKED` badge; maximum continuous safety cap: 10 minutes). Speak freely without holding any key, then tap **`⌃ Control`** once to finish and inject!
- Release or unlock: text is automatically capitalized, punctuated, and injected into your active text box.

---

## ✨ Core Capabilities

### 🎙️ Global Push-to-Talk & Live Streaming HUD
- **Local inference:** Transcription latency depends on hardware, audio duration and whether the model is warm.
- **Live 650ms Streaming:** A non-activating floating HUD pill displays partial words and an animated blinking cursor while you speak.
- **Zero Window Focus Theft:** The HUD uses an auxiliary `NSPanel` (`canBecomeKey = false`), ensuring your active text cursor never loses focus.

### ⌨️ Universal Auto-Paste Pipeline
Echo automatically routes text through an intelligent injection cascade:
1. **AXDirect Attribute Injection:** Replaces selected text directly in native Cocoa/AppKit controls with zero simulated keystrokes, without touching the clipboard.
2. **Clipboard Placement + Synthetic Cmd+V Paste:** Writes the transcript to `NSPasteboard.general`, pastes it with `.maskCommand` isolation and a settle delay, then restores the previous clipboard contents (all pasteboard items).
3. **Direct Unicode Typing:** Types complete Unicode graphemes via `CGEventKeyboardSetUnicodeString` at a 1.5ms cadency for inputs that reject paste events, again restoring the previous clipboard afterwards.
4. **Focused Target Protection:** Captures focused UI element and process ID prior to injection. If the user changes active windows during transcription, output is safely held on the clipboard with an informative HUD alert, preventing private text delivery into unintended apps.
5. **Interrupted Typing Recovery:** When synthetic typing is interrupted or cancelled, the unposted remainder suffix is written to the clipboard at a clean Unicode grapheme boundary rather than duplicating or discarding words.
6. **Origin-Bound Lifecycle:** `DictationLifecycle` coordinates audio capture, streaming previews, and delivery tokens, preventing stale or overlapping dictations from polluting new sessions.
7. **Manual Fallback:** If every synthetic path fails, the transcript stays on the clipboard so it is never lost.

### 👥 Bot-Free Dual-Channel Meeting Studio
- **Acoustic Loopback:** Uses macOS 14+ `ScreenCaptureKit` (`capturesAudio = true`, `excludesCurrentProcessAudio = true`) to capture meeting audio with zero acoustic echo.
- **Independent Multi-Consumer AudioHub:** Hardware-level retain counting and mutex locks allow microphone and ScreenCaptureKit loopback streams to be started, stopped, and shared concurrently without race conditions or orphaned audio handles.
- **Sample-Accurate VAD & Onset Timing:** Rolling energy VAD accumulates exact sample counts across variable callback buffers to eliminate timing jitter, stamping onset timestamps for chronological accuracy.
- **Graphite Frost Interface:** Native `NSVisualEffectView` frosted dark-gray surfaces with a cool frost-blue accent, using a 62/38 split layout separating conversation streams from live AI notes.
- **Incremental Notes & Persistent Tasks:** Action items and key decisions persist across launches in SQLite (`action_items` table). `IncrementalNotesExtractor` caches items by segment UUID ($O(1)$ lookups) instead of rescanning entire transcripts.
- **Markdown Notes Export:** Saves the current session as Markdown and writes a `.md` file to the configurable export folder (default `~/Documents/Echo Meetings`).
- **Process-Isolated Temp Storage:** Inference audio files live in private `tmp_audio/pid_<PID>/` directories (0700/0600 POSIX permissions). Orphan sweep verifies PID liveness before deletion.

### 🧠 Word Memory & Speech Lexicon Engine
- **Persistent Vocabulary:** Built-in SQLite database stores phonetic replacements (e.g. `"phone on"` → `"Phonon"`, `"anti gravity"` → `"Antigravity"`).
- **Whole-Word Boundary Accuracy:** Regular expressions (`\b(pattern)\b`) protect against destructive sub-word replacements.
- **In-App Management:** Click the **`Memory (n)`** button in Meeting Studio to add custom terms, view active hotwords, or remove entries.
- **Configurable Dictation Retention:** Standalone dictations can be set to Keep Forever, 30 Days, 7 Days, or Do Not Keep via the menu.
- **Resilient & Degraded Storage Modes:** SQLite migrations run in immediate transactions with automatic rollback. If durable storage is locked or unreadable, Echo alerts the user and provides an optional isolated in-memory temporary session mode.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| **Hold `⌃ Control`** | **Push-to-Talk Dictation** | Stream live speech into floating HUD; auto-paste on release |
| **`⇧⌘E`** | **Open Meeting Studio** | Toggle the frosted Meeting Studio window |
| **`⇧⌘D`** | **Toggle Dictation** | Programmatic push-to-talk toggle switch |
| **`⇧⌘C`** | **Copy Last Dictation** | Instantly re-copies most recent transcript to clipboard |
| **`⇧⌘R`** | **Start/Stop Meeting** | Begin or conclude dual-channel meeting recording |
| **`⌘Q`** | **Quit Echo** | Conclude audio streams and exit application |

The `⇧⌘` chords require Accessibility access to work while another app is frontmost. When Echo itself is focused they are dispatched by the app menu.

---

## 🏛️ Architecture

Detailed architectural documentation is available in [ARCHITECTURE.md](ARCHITECTURE.md).

```
                                  ┌─────────────────────────────┐
                                  │   ⌃ Control Push-to-Talk    │
                                  └──────────────┬──────────────┘
                                                 │
                   ┌─────────────────────────────┴─────────────────────────────┐
                   ▼                                                           ▼
      ┌────────────────────────┐                                 ┌───────────────────────────┐
      │   DictationLifecycle   │                                 │   MeetingCoordinator      │
      │ • Recording ID Token   │                                 │ • Dual-channel timeline   │
      │ • Target Focus Check   │                                 │ • IncrementalNotesExtractor│
      │ • Preview & Remainder  │                                 │ • Persistent Action Items │
      └────────────┬───────────┘                                 └─────────────┬─────────────┘
                   │                                                           │
                   └──────────────────────┬────────────────────────────────────┘
                                          ▼
                       ┌────────────────────────────────────┐
                       │          AppCoordinator            │
                       └──────────────────┬─────────────────┘
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  ▼                                               ▼
    ┌───────────────────────────┐                   ┌───────────────────────────┐
    │         AudioHub          │                   │ Phonon-2 Local STT Engine │
    │ • Multi-Consumer Retains  │                   │ • Process-Isolated Audio  │
    │ • 16kHz Mic Tap           │                   │ • FastConformer-TDT INT6  │
    │ • ScreenCaptureKit Loop   │                   │ • Configurable MLX / CPU  │
    │ • Sample-Accurate VAD     │                   │ • Bounded Queue Budget    │
    └─────────────┬─────────────┘                   └─────────────┬─────────────┘
                  │                                               │
                  └───────────────────────┬───────────────────────┘
                                          ▼
                         ┌─────────────────────────────────┐
                         │   WordMemory & SQLite Storage   │
                         │ • SQLite3 WAL Mode + Retries    │
                         │ • Word-Boundary Sanitization    │
                         │ • Configurable History Retention│
                         │ • In-Memory Temporary Failover  │
                         └────────────────┬────────────────┘
                                          ▼
                         ┌─────────────────────────────────┐
                         │       TextInjector Cascade      │
                         │ 1. AXDirect Attribute Insert    │
                         │ 2. Target Focus Verification    │
                         │ 3. Cmd+V Paste (Lease & Restore)│
                         │ 4. Unicode Typing + Remainder   │
                         │ 5. Safe Clipboard Fallback      │
                         └─────────────────────────────────┘
```

---

## 🛠️ Developer Guide

### Directory Layout

```
Echo/
├── Sources/Echo/
│   ├── Audio/               # AudioHub, CoreAudio tap, ScreenCaptureKit loopback, VAD, temp scratch
│   ├── Engine/              # Phonon process runner, STT types, MeetingCoordinator, NotesExtractor
│   ├── Injection/           # TextInjector, SystemEventPoster, HotkeyManager
│   ├── Storage/             # SQLite DatabaseManager, WordMemoryEngine, MeetingModels
│   ├── UI/                  # Floating HUD pill, MenuBarManager, DesignSystem
│   │   └── MeetingStudio/   # Frosted studio views, timeline, and controls
│   ├── DictationLifecycle.swift # Dictation state machine, focus binding, and recovery
│   ├── EchoSettings.swift   # Central user defaults, engine path, device, and retention
│   ├── AppCoordinator.swift # Central subsystem coordinator and lifecycle manager
│   ├── EchoApp.swift        # Application entry point, CLI flags (--test, --verify-speech)
│   └── main.swift           # Application bootstrap
├── Tests/EchoTests/         # 167 Swift Testing unit & integration tests across 15 suites
├── test_samples/            # 16kHz reference audio files for automated tests
├── AppIconSource.png        # Elk artwork used to build the app icon
├── AppIcon-1024.png         # Generated 1024px master icon
├── AppIcon.icns             # Multi-resolution macOS squircle icon
├── Echo.iconset/            # Generated icon sizes packed into AppIcon.icns
├── assemble_app.sh          # Automated release build, codesign, and bundle invariant self-test
├── build_app_icon.swift     # Renders the squircle icon + iconset from the source
├── make_icns.py             # Packs Echo.iconset into AppIcon.icns
├── Package.swift            # Swift package definition
├── ARCHITECTURE.md          # Systems architecture deep dive
├── ROADMAP.md               # Product roadmap and feature milestones
└── CHANGELOG.md             # Semantic version history
```

### Compiling from Source

Echo compiles with native command-line tools without external dependencies:

```bash
# Compile release binary with SQLite and AppKit/SwiftUI frameworks
swiftc -O -parse-as-library \
  -module-cache-path .build/ModuleCache \
  -target arm64-apple-macos14.0 \
  -lsqlite3 \
  -framework AppKit -framework ApplicationServices -framework AVFoundation -framework ScreenCaptureKit -framework SwiftUI \
  Sources/Echo/*.swift Sources/Echo/*/*.swift Sources/Echo/*/*/*.swift \
  -o echo-app
```

### Regenerating the App Icon

The icon is generated from `AppIconSource.png` (1024×1024) so it can be
rebuilt without design tools:

```bash
# Renders AppIcon-1024.png and Echo.iconset/ (824pt squircle, 100pt margins)
swift build_app_icon.swift

# Packs the iconset into a multi-resolution AppIcon.icns
python3 make_icns.py
```

Pass a different artwork path with `swift build_app_icon.swift path/to/art.png`.

### Packaging & Code Signing

Official updater-enabled releases offer **Check for Updates…** in the Echo menu. The [release setup guide](docs/releases.md) covers Developer ID signing, notarization, and publishing Sparkle updates.

Run `./assemble_app.sh` to compile the release binary, stage into `Echo.app`, embed the app icon, ad-hoc sign the bundle, and execute the automated self-test.

```bash
./assemble_app.sh
```

Moving a signed build into Applications or replacing it can require reauthorizing Echo in System Settings (**System Settings → Privacy & Security → Accessibility**).

### CLI Self-Tests & Diagnostics

Echo's binary provides built-in validation flags for verification and troubleshooting:

```bash
# Verify bundle structure, Info.plist, executable, and disposable database
./Echo.app/Contents/MacOS/Echo --test

# Verify engine binary availability in addition to bundle checks
./Echo.app/Contents/MacOS/Echo --test --require-engine

# Execute end-to-end inference against a test audio fixture
./Echo.app/Contents/MacOS/Echo --test --verify-speech test_samples/short_sample_16k.wav
```

### Configuration & User Defaults

Echo preferences can be customized via macOS `defaults` or environment variables:

| Setting Key | Environment Variable | Default | Description |
| :--- | :--- | :--- | :--- |
| `echo.fermionPath` | `ECHO_FERMION_PATH` | Discovered in `PATH` | Absolute path to the `fermion` CLI executable |
| `echo.fermionDevice` | `ECHO_FERMION_DEVICE` | `cpu` | Inference device (`cpu`, `mps`, `mlx`, `metal`) |
| `echo.dictationRetention` | — | `forever` | History retention (`forever`, `thirtyDays`, `sevenDays`, `disabled`) |
| `echo.exportDirectory` | — | `~/Documents/Echo Meetings` | Target directory for exported meeting Markdown files |

Example custom configuration:
```bash
defaults write com.ragavij.echo echo.fermionPath "$HOME/Library/Application Support/Echo/engine/bin/fermion"
defaults write com.ragavij.echo echo.fermionDevice mlx
defaults write com.ragavij.echo echo.dictationRetention thirtyDays
defaults write com.ragavij.echo echo.exportDirectory "$HOME/Documents/Obsidian/Meetings"
```

### Running Automated Test Suites

```bash
# Primary suite: Swift Testing (167 tests across 15 suites)
# Tests audio store, converter, sample-accurate VAD, multi-consumer AudioHub,
# DictationLifecycle, TextInjector cascade & remainder recovery, SQLite migrations,
# IncrementalNotesExtractor, MeetingSession export, and user settings.
swift test
```

On a Command Line Tools-only install (no Xcode selected), Swift Testing's macro
plugin has to be pointed at explicitly:

```bash
swift test -Xswiftc -plugin-path \
  -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
```

Legacy standalone harnesses (kept for manual end-to-end checks):

```bash
# SQLite & Word Memory harness (5/5)
swiftc -module-cache-path .build/ModuleCache -target arm64-apple-macos14.0 -lsqlite3 \
  Sources/Echo/Audio/*.swift Sources/Echo/Engine/STTTypes.swift Sources/Echo/Storage/*.swift \
  test_database.swift -o test_database && ./test_database

# Text Injection & Auto-Paste harness (4/4)
swiftc -module-cache-path .build/ModuleCache -target arm64-apple-macos14.0 -lsqlite3 \
  -framework AppKit -framework ApplicationServices -framework AVFoundation -framework ScreenCaptureKit -framework SwiftUI \
  Sources/Echo/Audio/*.swift Sources/Echo/Engine/*.swift Sources/Echo/Injection/*.swift \
  Sources/Echo/Storage/*.swift Sources/Echo/UI/*.swift Sources/Echo/UI/MeetingStudio/*.swift \
  Sources/Echo/AppCoordinator.swift test_injection.swift -o test_injection && ./test_injection
```

---

## 📄 License

Echo is released under the **MIT License**. See [LICENSE](LICENSE) for details.
