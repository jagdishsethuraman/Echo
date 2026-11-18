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
3. **Local SQLite & Word Memory:** Every session and dictation is archived in local SQLite (`echo.sqlite`). A built-in lexicon engine learns personal vocabulary, project jargon, and acronyms, automatically correcting phonetically misheard terms in real time.

---

## ⚡ Quick Start

### 1. Download or Run the App
Launch `Echo.app` directly from your Applications folder or workspace:
```bash
open /Users/ragavij/Documents/Developer/Echo/Echo.app
```

### 2. Grant macOS Accessibility Permission (One-Time)
Echo requires Accessibility permissions to monitor the `⌃ Control` hotkey and paste text into your active applications:
1. Open **System Settings → Privacy & Security → Accessibility**.
2. Select **Echo** and toggle it **ON**.
*(Echo uses a permanent designated requirement so permissions survive future rebuilds).*

### 3. Start Dictating
- Press and hold **`⌃ Control`** in any application (Notion, Slack, Chrome, VS Code, Notes, TextEdit, Terminal).
- **Hands-Free Lock Mode:** Double-tap **`⌃ Control`** rapidly to lock recording on (displays `🔒 LOCKED` badge). Speak freely for as long as you want without holding any key, then tap **`⌃ Control`** once to finish and inject!
- Release or unlock: text is automatically capitalized, punctuated, and injected into your active text box.

---

## ✨ Core Capabilities

### 🎙️ Global Push-to-Talk & Live Streaming HUD
- **Sub-150ms Latency:** Powered by `fermionresearch/phonon-2` (Parakeet-TDT 0.6B INT6), delivering **37.7x real-time factor**.
- **Live 650ms Streaming:** A non-activating floating HUD pill displays partial words and an animated blinking cursor while you speak.
- **Zero Window Focus Theft:** The HUD uses an auxiliary `NSPanel` (`canBecomeKey = false`), ensuring your active text cursor never loses focus.

### ⌨️ Universal Auto-Paste Pipeline
Echo automatically routes text through a 3-tier injection cascade:
1. **Permanent Pasteboard Save:** Declares text on `NSPasteboard.general` without wiping, guaranteeing manual `Cmd+V` fallback.
2. **AXDirect Attribute Injection:** Replaces selected text directly in native Cocoa/AppKit controls with zero simulated keystrokes.
3. **Synthetic Cmd+V Paste:** Employs `.maskCommand` isolation and a 30ms settle delay to paste instantaneously across 100% of macOS apps.
4. **Direct Unicode Typing:** Types UTF-16 code units via `CGEventKeyboardSetUnicodeString` at a 1.5ms cadency for inputs that reject paste events.

### 👥 Bot-Free Dual-Channel Meeting Studio
- **Acoustic Loopback:** Uses macOS 14+ `ScreenCaptureKit` (`capturesAudio = true`, `excludesCurrentProcessAudio = true`) to capture meeting audio with zero acoustic echo.
- **Rolling Energy VAD:** Automatically segments speech upon 600ms natural silence boundaries.
- **Graphite Frost Interface:** Native `NSVisualEffectView` frosted dark-gray surfaces with a cool frost-blue accent, using a 62/38 split layout separating conversation streams from live AI notes.
- **1-Click Obsidian Export:** Exports structured Markdown notes directly to your Second Brain or clipboard.

### 🧠 Word Memory & Speech Lexicon Engine
- **Persistent Vocabulary:** Built-in SQLite database stores phonetic replacements (e.g. `"phone on"` → `"Phonon"`, `"anti gravity"` → `"Antigravity"`).
- **Whole-Word Boundary Accuracy:** Regular expressions (`\b(pattern)\b`) protect against destructive sub-word replacements.
- **In-App Management:** Click the **`Memory (n)`** button in Meeting Studio to add custom terms, view active hotwords, or remove entries.

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

---

## 🏛️ Architecture

Detailed architectural documentation is available in [ARCHITECTURE.md](ARCHITECTURE.md).

```
                                  ┌─────────────────────────────┐
                                  │   ⌃ Control Push-to-Talk    │
                                  └──────────────┬──────────────┘
                                                 │
                  ┌──────────────────────────────┴──────────────────────────────┐
                  ▼                                                             ▼
     ┌────────────────────────┐                                   ┌───────────────────────────┐
     │  Floating HUD Panel    │                                   │    Meeting Studio Window  │
     │  • Non-activating NSPanel│                                  │    • Graphite Frost glass │
     │  • Live 650ms Stream   │                                   │    • 62/38 Split Timeline │
     │  • Audio Waveform VU   │                                   │    • Word Memory Drawer   │
     └────────────┬───────────┘                                   └─────────────┬─────────────┘
                  │                                                             │
                  └──────────────────────┬──────────────────────────────────────┘
                                         ▼
                      ┌────────────────────────────────────┐
                      │          AppCoordinator            │
                      └──────────────────┬─────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
   ┌───────────────────────────┐                   ┌───────────────────────────┐
   │ CoreAudio / ScreenCapture │                   │ Phonon-2 Local STT Engine │
   │ • 16kHz Mic Tap           │                   │ • FastConformer-TDT INT6  │
   │ • Speaker Loopback        │                   │ • Metal / MLX Accelerated │
   │ • Rolling 0.6s Energy VAD │                   │ • Sub-150ms Latency       │
   └─────────────┬─────────────┘                   └─────────────┬─────────────┘
                 │                                               │
                 └───────────────────────┬───────────────────────┘
                                         ▼
                        ┌─────────────────────────────────┐
                        │      WordMemoryEngine           │
                        │ • SQLite3 Lexicon (WAL Mode)    │
                        │ • Word-Boundary Sanitization    │
                        └────────────────┬────────────────┘
                                         ▼
                        ┌─────────────────────────────────┐
                        │       TextInjector Cascade      │
                        │ 1. Clipboard Placement          │
                        │ 2. AXDirect Attribute Insert    │
                        │ 3. Synthetic Cmd+V Auto-Paste   │
                        │ 4. Unicode Typing Fallback      │
                        └─────────────────────────────────┘
```

---

## 🛠️ Developer Guide

### Directory Layout

```
Echo/
├── Sources/Echo/
│   ├── Audio/               # CoreAudio tap, ScreenCaptureKit loopback, VAD, WAV encoder
│   ├── Engine/              # Phonon process runner, STT types, MeetingCoordinator
│   ├── Injection/           # TextInjector, SystemEventPoster, HotkeyManager
│   ├── Storage/             # SQLite DatabaseManager, WordMemoryEngine, MeetingModels
│   ├── UI/                  # Floating HUD pill, MenuBarManager, DesignSystem
│   │   └── MeetingStudio/   # Frosted studio views, timeline, and controls
│   └── main.swift           # Application entry point & lifecycle
├── test_samples/            # 16kHz reference audio files for automated tests
├── AppIconSource.png        # Elk artwork used to build the app icon
├── AppIcon-1024.png         # Generated 1024px master icon
├── AppIcon.icns             # Multi-resolution macOS squircle icon
├── Echo.iconset/            # Generated icon sizes packed into AppIcon.icns
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

To preserve macOS Accessibility permissions across builds, seal the bundle with an explicit designated requirement:

```bash
# 1. Stage into .app bundle
mkdir -p Echo.app/Contents/MacOS Echo.app/Contents/Resources
cp echo-app Echo.app/Contents/MacOS/Echo
cp AppIcon.icns Echo.app/Contents/Resources/AppIcon.icns

# 2. Ad-hoc sign with permanent designated requirement
codesign --force --deep --sign - \
  --identifier com.ragavij.echo \
  -r="designated => identifier \"com.ragavij.echo\"" \
  Echo.app
```

### Running Automated Test Suites

```bash
# Primary suite: Swift Testing (audio store, converter, VAD, SQLite,
# word memory, formatting/injection, export, settings)
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

# Full app subsystem verification (3/3)
./Echo.app/Contents/MacOS/Echo --test
```

---

## 📄 License

Echo is released under the **MIT License**. See [LICENSE](LICENSE) for details.
