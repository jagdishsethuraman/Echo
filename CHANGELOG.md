# Changelog

All notable changes to **Echo** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed
- **Shared audio hub:** Dictation and meeting capture now share one `AudioEngineManager` through a reference-counted `AudioHub` instead of opening two taps on the same microphone. Buffers and meters fan out to multiple observers, so one consumer can no longer silently replace another.
- **Bounded transcription queue:** Meeting segments are transcribed through `TranscriptionService` with a single in-flight engine process (configurable) instead of one unbounded `fermion` process per VAD segment. `stopSession()` now waits (up to 5 s) for the queue to drain before writing `endTime`, so the final utterance is included in the session and export.
- **VAD pre-roll:** The detector keeps a configurable 300 ms pre-roll buffer and prepends it when speech starts, preventing clipped word onsets. Segment callbacks are now delivered synchronously so shutdown can observe the final segment.
- **Native "Graphite Frost" interface:** Replaced the black/brass/lavender theme with a neutral frosted graphite palette, a cool frost-blue primary accent, and a sea-glass secondary accent. Typography now uses SF Pro with monospaced digits only where telemetry benefits from them.
- **Meeting Studio redesign:** The window now uses real `NSVisualEffectView` vibrancy with a dark appearance, hidden titlebar, autosaved frame, and a unified toolbar-style header showing the session title, recording state, input meters, word memory, and record control. The accessibility notice is a quiet inline banner instead of an amber warning strip.
- **Transcript & Notes:** Transcript rows use native list spacing with speaker avatars, hover-to-copy, and subtle selection; the notes inspector has frosted cards, action-item progress (`2/4`), and a pinned accent export button.
- **HUD & menu bar:** The floating pill shares the graphite glass treatment with the frost-blue waveform. The menu-bar item uses SF Symbols for idle, dictating, and recording states, and menu copy was shortened to match macOS conventions.
- **App icon:** Replaced the old icon with the elk artwork, rebuilt on Apple's 824pt squircle grid with a soft dock shadow and hairline rim. The source, 1024px master, iconset, and regeneration scripts now live in the repo.
- **Developer tooling:** Debug builds accept `Echo --snapshot <directory>` to render PNGs of the studio and HUD, and Xcode `#Preview`s cover both surfaces for design iteration.

### Fixed
- **Safe SQLite database fallback:** Added graceful `NSTemporaryDirectory()` fallback in `DatabaseManager` ensuring tables are created and operations proceed even under restricted sandbox permissions.
- **Accessibility injection safety:** Guarded `focusedElement` with `CFGetTypeID` against unexpected CFTypes before casting to `AXUIElement` (`CORE-03`).
- **Eliminated double SwiftUI invalidation:** Removed redundant manual `objectWillChange.send()` calls when mutating `@Published` properties (`CORE-02`).

---

## [1.2.0] - 2026-11-17

### Added
- **Control Key Push-to-Talk (`⌃`):** Migrated primary global dictation hotkey from Right Option to Control key to avoid collisions with macOS shortcuts and screenshot combinations.
- **Hands-Free Double-Tap Lock Mode:** Double-tapping `⌃` within 380ms locks dictation into hands-free mode. Displays an amber `🔒 LOCKED` badge in the pill HUD. Tapping `⌃` once unlocks and injects text.
- **Intelligent Sentence Capitalization & Proper Noun Engine:** Built `formatSentencePunctuationAndCapitalization` capitalizing first letters after sentence terminators (`. `, `? `, `! `, `\n`), fixing pronoun `"I"` and contractions (`"I'm"`, `"I'll"`, `"I've"`, `"I'd"`), and preserving proper nouns (`macOS`, `iPhone`).
- **Dynamic Bottom-Center Pill HUD:** Centered HUD 28px above Dock/taskbar out of the user's line of sight; dynamically expands width between 260px and 720px as speech length grows without truncating beginning words.
- **AppleScript System Events Paste Fallback:** Added tertiary keystroke injection path ensuring universal auto-paste across all macOS applications.

### Fixed
- **Eliminated Janky Gray Box Artifact:** Replaced rectangular window-clipped shadow with native seamless `Capsule()` styling and cleared `NSHostingView` layer background.
- **Eliminated Defensive Permission Blocks:** Removed over-defensive `guard AXIsProcessTrusted()` checks in `typeUnicodeString` and `postCmdV` allowing auto-paste to fire reliably.
- **Removed Head Truncation:** Switched transcription streaming text from `.truncationMode(.head)` to `.truncationMode(.tail)` so users read complete full sentences as they speak.

---

## [1.1.0] - 2026-11-17

### Added
- **Local SQLite Backend (`echo.sqlite`):** Native `libsqlite3` persistence with Write-Ahead Logging (`PRAGMA journal_mode = WAL`) and normal synchronization. Stores `sessions`, `utterances`, and `dictionary` tables across app restarts.
- **Word Memory & Speech Lexicon Engine:** Built `WordMemoryEngine` featuring whole-word boundary regex sanitization (`\b(pattern)\b`) correcting phonetically ambiguous STT outputs (e.g. `"phone on"` → `"Phonon"`, `"anti gravity"` → `"Antigravity"`) in real time.
- **Seeded Project Vocabulary:** Initialized default high-accuracy replacements for `Phonon`, `Antigravity`, `Parakeet`, `Meetily`, `Bento`, `Ragav`, and `Swiss Atelier`.
- **Interactive Word Memory Drawer:** Added `Memory (n)` control in the Meeting Studio top bar featuring inline addition of misheard/preferred pairs and 1-click chip deletion.
- **Workspace Fallback:** Automatic sandbox-safe fallback to `./data/echo.sqlite` if macOS `~/Library/Application Support/` access is restricted.
- **Automated Database Tests:** Added `test_database.swift` validating session storage, utterance persistence, dictation isolation, word boundary safety, and dynamic learning.

### Changed
- `MeetingCoordinator` now automatically restores previous meeting sessions and past utterances from SQLite on app startup.
- `AppCoordinator` applies Word Memory sanitization to both the 650ms live streaming HUD and the final text cursor injection.

---

## [1.0.0] - 2026-11-17

### Added
- **Live Transcription Streaming:** Built rolling 650ms partial transcription loop streaming live recognized words into the floating HUD with an animated blinking cursor while speaking.
- **Universal Auto-Paste Pipeline:** Upgraded `TextInjector` with a 3-tier cascade: `AXUIElement` direct value replacement → synthetic `Cmd+V` (with 30ms settle delay and `.maskCommand` isolation) → direct Unicode typing fallback (`CGEventKeyboardSetUnicodeString` at 1.5ms cadency).
- **Permanent TCC Code Signing:** Sealed `Echo.app` bundle with designated requirement `-r="designated => identifier \"com.ragavij.echo\""` eliminating accessibility permission invalidation on recompiles.
- **Automated Test Harnesses:** Added `test_injection.swift` verifying text preparation, direct Unicode typing, clipboard retention, and meeting timeline integration.
- **Production Packaging:** Assembled native standalone macOS app bundle `Echo.app` with Retina `AppIcon.icns`.

### Fixed
- Fixed repeating `"Echo" would like to control this Mac...` modal alert loop by removing intrusive `promptIfNeeded: true` calls during the injection cycle.
- Fixed WindowServer synthetic keystroke drops by verifying `AXIsProcessTrusted()` before dispatching events.
- Scoped `HotkeyManager` strictly to `[.flagsChanged]`, removing unnecessary `.keyDown`/`.keyUp` global monitoring.

---

## [0.5.0] - 2026-11-16

### Added
- **Spike 5 (Rolling VAD & Meeting Studio):** Implemented dual-channel `VoiceActivityDetector` dynamically slicing speech upon 600ms natural silence boundaries.
- **Swiss Atelier Bento Studio:** Built `MeetingStudioView` and `TranscriptTimelineView` with a 62/38 Bento grid, obsidian `#050507` and warm brass `#e5a93c` palette, live audio meters, and meeting timer.
- **Obsidian / Markdown Exporter:** 1-click exporter generating clean structured Markdown summaries with timestamps, speakers, and action items.

---

## [0.4.0] - 2026-11-16

### Added
- **Spike 4 (Dual-Channel Audio Loopback):** Built CoreAudio `AudioEngineManager` (16kHz microphone tap with automatic hardware resampling) and `SystemAudioCapture` (`ScreenCaptureKit` with `capturesAudio = true`, `excludesCurrentProcessAudio = true`).
- **Zero-Echo Loopback:** Isolated system speaker audio without physical microphone feedback or virtual soundcard dependencies.
- **Speaker Separation:** Implemented `DualChannelCoordinator` tagging incoming audio into `.you` vs `.meeting` tracks.

---

## [0.3.0] - 2026-11-16

### Added
- **Spike 3 (Text Injection Engine):** Implemented `TextInjector` supporting dual injection strategies: `AXUIElement` direct text replacement and synthetic receipt-sequenced `Cmd+V` paste.
- **Non-Destructive Clipboard Retention:** Preserved user's clipboard contents on `NSPasteboard.general` for guaranteed paste fallback.

---

## [0.2.0] - 2026-11-16

### Added
- **Spike 2 (Non-Activating Floating HUD):** Implemented `FloatingPillPanel` (`NSPanel` with `.nonactivatingPanel`, `canBecomeKey=false`, `.floating` level) ensuring zero window-focus theft from active apps.
- **Adaptive Pill Menu Bar:** Built `MenuBarManager` supporting dynamic transitions between idle glyph `◉`, dictating state, and live meeting recording timer `● MM:SS`.

---

## [0.1.0] - 2026-11-16

### Added
- **Spike 1 (Phonon-2 Native Swift Benchmark):** Built `PhononProcessRunner` and `PhononClient` bridging `fermionresearch/phonon-2` (158 MB INT6 Parakeet-TDT 0.6B) locally on Apple Silicon.
- **Benchmark Results:** Confirmed 20.01s 16kHz mono audio stream decoded in 1.42s wall time (0.53s pure model decode, 37.7x real-time), with 0 silence hallucinations.
