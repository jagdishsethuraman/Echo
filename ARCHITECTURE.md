# Echo — Architectural Specification & Engineering Deep Dive

This document details the internal systems architecture, audio pipelines, data flows, and security model of **Echo**.

---

## 🏛️ System Topology

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       HOST OPERATING SYSTEM                                     │
│                                (macOS 14+ Sonoma / Sequoia · Apple Silicon)                     │
└──────────────────────────────────────────────┬──────────────────────────────────────────────────┘
                                               │
               ┌───────────────────────────────┴───────────────────────────────┐
               ▼                                                               ▼
   ┌───────────────────────┐                                       ┌───────────────────────┐
   │ CoreAudio Input Tap   │                                       │ ScreenCaptureKit Tap  │
   │ • 16kHz Mono Resample │                                       │ • System Audio Stream │
   │ • Logarithmic VU RMS  │                                       │ • Process Exclusion   │
   └───────────┬───────────┘                                       └───────────┬───────────┘
               │                                                               │
               │ (Mic PCM Buffer)                                              │ (Speaker PCM Buffer)
               ▼                                                               ▼
   ┌───────────────────────────────────────────────────────────────────────────────────────┐
   │                               DualChannelCoordinator                                  │
   │                          • VoiceActivityDetector (0.08 Energy, 0.6s Silence)          │
   │                          • Canonical RIFF/WAVE 16kHz Mono Encoder                     │
   └───────────────────────────────────────────┬───────────────────────────────────────────┘
                                               │
                                               │ (WAV Audio Packets)
                                               ▼
   ┌───────────────────────────────────────────────────────────────────────────────────────┐
   │                                 PhononProcessRunner                                   │
   │                   • fermionresearch/phonon-2 (158 MB INT6 Parakeet-TDT)              │
   │                   • CPU by default; override with ECHO_FERMION_DEVICE                 │
   │                   • Sub-150ms Decoding Latency (37.7x Real-Time Factor)               │
   └───────────────────────────────────────────┬───────────────────────────────────────────┘
                                               │
                                               │ (Raw Hypotheses)
                                               ▼
   ┌───────────────────────────────────────────────────────────────────────────────────────┐
   │                                  WordMemoryEngine                                     │
   │               • In-Memory Lexicon Cache (Longest-Pattern-First Match)                 │
   │               • Word-Boundary Regex Sanitizer: \b(pattern)\b                          │
   │               • Dynamic Vocabulary Learning & Frequency Counter                       │
   └───────────────────┬───────────────────────────────────────────────┬───────────────────┘
                       │                                               │
                       ▼                                               ▼
   ┌────────────────────────────────────────┐      ┌───────────────────────────────────────┐
   │           TextInjector Engine          │      │         Local Database Backend        │
   │  1. Permanent NSPasteboard Save        │      │  • SQLite3 (WAL Mode, Normal Sync)    │
   │  2. AXUIElement Direct Attribute Set   │      │  • Sessions Table (Metadata/Notes)    │
   │  3. Synthetic Cmd+V Auto-Paste         │      │  • Utterances Table (Speakers/Audio)  │
   │  4. Direct Unicode Typing Fallback     │      │  • Dictionary Table (Hotwords)        │
   └───────────────────┬────────────────────┘      └───────────────────────────────────────┘
                       │
                       ▼
       ┌───────────────────────────────┐
       │ Active Text Field Anywhere    │
       │ (Notion / Slack / Chrome /    │
       │  VS Code / Notes / Terminal)  │
       └───────────────────────────────┘
```

---

## 🎙️ Subsystem 1: Dual Audio Pipelines

Echo operates two isolated, high-performance audio capture pipelines concurrently:

### 1. Microphone Tap (`AudioEngineManager.swift`)
- Uses `AVAudioEngine` attached to `inputNode`.
- Captures native hardware audio and converts it to canonical **16,000 Hz, 1-channel (mono), 16-bit linear PCM**.
- Computes real-time Root-Mean-Square (RMS) amplitude normalized logarithmically between `0.0` and `1.0` for dynamic UI waveform bars and VU meters.

### 2. System Speaker Loopback (`SystemAudioCapture.swift`)
- Leverages macOS 14+ `ScreenCaptureKit` stream with `capturesAudio = true`.
- **Acoustic Isolation:** Configures `excludesCurrentProcessAudio = true`, guaranteeing that sound generated by Echo itself is never recaptured.
- Completely eliminates physical feedback loops and requires **zero virtual soundcards** (like BlackHole or Soundflower) and **zero external meeting bots**.

### 3. Voice Activity Detection (`VoiceActivityDetector.swift`)
- Dual independent VAD engines monitor microphone (`.you`) and system audio (`.meeting`).
- Evaluates RMS energy against an adaptive threshold (`0.08`).
- Slices audio chunks upon **600ms of sustained silence**, emitting complete natural sentences to the speech engine without clipping mid-word.

---

## ⚡ Subsystem 2: Speech Recognition Engine

Echo uses `fermionresearch/phonon-2` as its core speech engine:
- **Model Architecture:** FastConformer Token-and-Duration Transducer (TDT) 0.6B.
- **Quantization:** INT6 (158 MB total disk and RAM footprint).
- **Inference Runtime:** Local process runner invoking `fermion`. The device is selected with `ECHO_FERMION_DEVICE` and defaults to `cpu`; Metal/MLX acceleration is not enabled by default yet (`BUILD-04`).
- **Performance Characteristics:**
  - Decodes 20.01 seconds of speech in **0.53 seconds** (pure model decode), achieving a **37.7x Real-Time Factor (RTF)**.
  - Zero silence hallucinations: FastConformer-TDT inherently suppresses phantom tokens during background noise or silence.
- **Rolling Partial Loop:** Every **650ms** during active dictation, a snapshot of the PCM buffer is packaged into a temporary WAV and transcribed to drive live streaming words in the floating HUD.

---

## ⌨️ Subsystem 3: Universal Text Injection Engine

The text injection pipeline (`TextInjector.swift`) delivers recognized text into any focused macOS application without requiring manual user intervention:

### Injection Cascade (AX → Paste → Typing)
1. **Clipboard Placement:** Text is sanitized and written to `NSPasteboard.general`. The previous contents are replaced by default; enabling `restorePreviousClipboard` restores them after a successful paste. The clipboard also acts as a manual fallback if an application blocks synthetic events.
2. **Path 1 — Accessibility Direct (`tryDirectAccessibilityInjection`):**
   Queries `kAXFocusedUIElementAttribute` via `AXUIElementCreateSystemWide()`. If `kAXSelectedTextAttribute` is settable, updates the text value instantly with zero keystrokes.
3. **Path 2 — Synthetic `Cmd+V` Paste (`postCmdV`):**
   Synthesizes a hardware `kVK_ANSI_V (0x09)` keystroke via `CGEvent`. Cleans lingering modifier keys by explicitly enforcing `.maskCommand` and introduces a **25ms settle delay** (plus a 25ms hold) after the physical `Control` key is released.
4. **Path 3 — Direct Unicode Keystroke Typing (`typeUnicodeString`):**
   Iterates through UTF-16 code units and calls `CGEventKeyboardSetUnicodeString` at a **1.5ms cadency**, typing directly into inputs that refuse pasteboard actions.

---

## 💾 Subsystem 4: Local SQLite Backend & Speech Lexicon

### Database Architecture (`DatabaseManager.swift`)
Echo utilizes the native macOS system SQLite library (`import SQLite3` / `libsqlite3.dylib`).

- **Storage Location:** `~/Library/Application Support/Echo/echo.sqlite` (with an automatic fallback to `./data/echo.sqlite` when sandboxed).
- **Concurrency & Integrity:**
  ```sql
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = NORMAL;
  ```

### Database Schema
```sql
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    start_time REAL NOT NULL,
    end_time REAL,
    summary_markdown TEXT,
    created_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS utterances (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    speaker TEXT NOT NULL,
    timestamp REAL NOT NULL,
    text TEXT NOT NULL,
    duration_seconds REAL NOT NULL,
    is_dictation INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_utterances_session ON utterances(session_id);
CREATE INDEX IF NOT EXISTS idx_utterances_timestamp ON utterances(timestamp);

CREATE TABLE IF NOT EXISTS dictionary (
    id TEXT PRIMARY KEY,
    raw_pattern TEXT NOT NULL UNIQUE,
    preferred_replacement TEXT NOT NULL,
    frequency INTEGER NOT NULL DEFAULT 1,
    case_sensitive INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dictionary_pattern ON dictionary(raw_pattern);
```

### Word Memory Engine (`WordMemoryEngine.swift`)
- Maintains an in-memory cache of dictionary entries sorted descending by pattern length.
- Matches whole-word boundaries using `\b(escapedPattern)\b` to prevent destructive substring replacements (e.g., `"phone on"` does not replace within `"saxophone on"`).
- Automatically updates frequency metrics upon reinforcement.

---

## 🖥️ Subsystem 5: User Interface Hierarchy

- **Floating HUD Pill (`FloatingPillPanel.swift`):**
  - Inherits from `NSPanel` with style mask `[.borderless, .nonactivatingPanel]`.
  - Properties: `canBecomeKey = false`, `canBecomeMain = false`, level `.statusBar`.
  - Anchors dynamically to the display containing the mouse cursor (`NSMouseInRect`).
  - Never steals window focus or disrupts the user's active typing cursor.
- **Meeting Studio (`MeetingStudioWindow.swift`):**
  - Standard floating utility window (`880x600`) with `.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`.
  - 62/38 Bento grid separating live conversation timeline from executive AI action items.
- **Adaptive Menu Bar Item (`MenuBarManager.swift`):**
  - `NSStatusItem` displaying minimal glyph `◉` when idle, and transitioning to `● MM:SS` during recording sessions via live timer.

---

## 🔒 Subsystem 6: macOS Security, TCC & Code Signing

### The Ad-Hoc CDHash Invalidation Problem
By default, ad-hoc codesigning (`codesign -s -`) pins the designated requirement to the Code Directory Hash (`cdhash`):
```bash
# designated => cdhash H"8d6069d27af93b91a7167666a3aab23f3e18ef42"
```
Whenever an ad-hoc binary is recompiled, its hash changes. Even though macOS System Settings continues to display the app toggle as `ON`, the TCC daemon (`tccd`) rejects the new binary as untrusted because its requirement fails, causing `AXIsProcessTrusted()` to return `false` and WindowServer to drop synthetic keystrokes.

### Permanent Resolution
Echo explicitly overrides the designated requirement during code signing:
```bash
codesign --force --deep --sign - \
  --identifier com.ragavij.echo \
  -r="designated => identifier \"com.ragavij.echo\"" \
  Echo.app
```
This binds TCC permissions permanently to the bundle identifier `com.ragavij.echo`, allowing developers to recompile and run new builds without losing Accessibility permissions.
