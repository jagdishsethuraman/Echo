# Echo — Native macOS Speech Intelligence

> Unified push-to-talk cursor dictation, live streaming speech recognition, and bot-free dual-channel meeting intelligence for Apple Silicon. Powered 100% offline by `fermionresearch/phonon-2` (158 MB INT6 Parakeet-TDT 0.6B).

---

## ✨ Features

- **Global Quick Dictation (Push-to-Talk):** Hold `Right ⌥` to speak anywhere in macOS. Speech recognition runs with 37.7x real-time speed.
- **Live Transcription Streaming:** Words stream live every 650ms into a non-activating floating HUD pill with dynamic audio waveform meters and blinking cursor.
- **Universal Auto-Paste:** Upon hotkey release, transcripts are immediately pasted or typed directly into the active text field (Notion, Slack, Chrome, VS Code, Notes, TextEdit, Terminal) with permanent clipboard retention.
- **Bot-Free Meeting Studio:** Dual-channel CoreAudio microphone tap combined with ScreenCaptureKit system audio loopback (`excludesCurrentProcessAudio = true`) isolates your voice from remote attendees without bots or virtual audio drivers.
- **Swiss Atelier Bento Interface:** Dark mode studio (`#050507` obsidian, `#e5a93c` warm brass) featuring 62/38 Bento split, live VU meters, conversation stream, and executive notes.
- **Adaptive Pill Menu Bar:** Sleek menu bar item dynamically adapting from minimal glyph `◉` to active recording timer `● MM:SS`.
- **Local SQLite Backend (`echo.sqlite`):** Native WAL-mode database persistently storing sessions, timestamps, speaker tracks, and every quick dictation across app restarts.
- **Word Memory & Custom Vocabulary:** Embedded lexicon engine remembering terms and autocorrecting phonetically misheard words (e.g. `"phone on"` → `"Phonon"`, `"anti gravity"` → `"Antigravity"`) in real time across live streams and active cursor typing.
- **1-Click Second Brain / Obsidian Sync:** Direct export to clean Markdown notes with timestamps, duration, and speaker tags.
- **100% Private & Offline:** Zero external cloud dependencies, zero telemetry, zero model RAM duplication (single native binary).

---

## 🏗️ Architecture

```
                                  ┌─────────────────────────────┐
                                  │   Right ⌥ Push-to-Talk      │
                                  └──────────────┬──────────────┘
                                                 │
                  ┌──────────────────────────────┴──────────────────────────────┐
                  ▼                                                             ▼
     ┌────────────────────────┐                                   ┌───────────────────────────┐
     │  Floating HUD Panel    │                                   │    Meeting Studio Window  │
     │  • Non-activating NSPanel│                                  │    • Swiss Atelier Bento  │
     │  • Live 650ms Stream   │                                   │    • 62/38 Split Timeline │
     │  • Audio Waveform VU   │                                   │    • Dual Channel Loops   │
     └────────────┬───────────┘                                   └─────────────┬─────────────┘
                  │                                                             │
                  ▼                                                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                     AppCoordinator                                          │
└───────────────────┬─────────────────────────────────────────────────────┬───────────────────┘
                    │                                                     │
                    ▼                                                     ▼
    ┌──────────────────────────────┐                      ┌──────────────────────────────┐
    │  Audio & Loopback Pipeline   │                      │  Phonon-2 Local STT Engine   │
    │  • CoreAudio 16kHz Mic       │                      │  • Parakeet-TDT 0.6B INT6    │
    │  • ScreenCaptureKit Loopback │                      │  • 158 MB Model Footprint    │
    │  • VoiceActivityDetector     │                      │  • Metal / MLX Accelerated   │
    └──────────────┬───────────────┘                      └──────────────┬───────────────┘
                   │                                                     │
                   └──────────────────────┬──────────────────────────────┘
                                          ▼
                         ┌─────────────────────────────────┐
                         │      Text Injection Engine      │
                         │  1. Permanent NSPasteboard Save │
                         │  2. AXUIElement Direct Insertion│
                         │  3. Synthetic Cmd+V Auto-Paste  │
                         │  4. Unicode Direct Keystrokes   │
                         └─────────────────────────────────┘
```

---

## 🚀 Building & Packaging

### Prerequisites
- macOS 14.0+ (Sonoma or Sequoia) on Apple Silicon (M1/M2/M3/M4).
- Swift 5.10 / 6.0 command-line tools.
- Phonon-2 runtime (`fermion`).

### Build Standalone App Bundle

```bash
# 1. Compile native binary
swiftc -O -parse-as-library \
  -target arm64-apple-macos14.0 \
  -framework AppKit -framework ApplicationServices -framework AVFoundation -framework ScreenCaptureKit -framework SwiftUI \
  Sources/Echo/*.swift Sources/Echo/*/*.swift Sources/Echo/*/*/*.swift \
  -o echo-app

# 2. Package into macOS App Bundle
mkdir -p Echo.app/Contents/MacOS Echo.app/Contents/Resources
cp echo-app Echo.app/Contents/MacOS/Echo
cp AppIcon.icns Echo.app/Contents/Resources/AppIcon.icns

# 3. Ad-hoc code sign with permanent designated requirement
codesign --force --deep --sign - \
  --identifier com.ragavij.echo \
  -r="designated => identifier \"com.ragavij.echo\"" \
  Echo.app
```

---

## 🔒 macOS Permissions

Echo requires **Accessibility** permission to synthesize paste/typing events into target applications and monitor the `Right ⌥` push-to-talk hotkey:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Add **Echo.app** and toggle **ON**.
*(The application code signature uses `identifier "com.ragavij.echo"`, preserving permission across rebuilds).*

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
