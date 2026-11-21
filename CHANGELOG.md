# Changelog

All notable changes to **Echo** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.5.0] - 2026-11-20

### Added
- **Persistent action items & decisions (#6):** Added dedicated `action_items` table in SQLite (`user_version = 3`) with stable UUIDs and `is_done` flags. Action items and their completion states persist across app restarts and view recreations, completely isolated by session ID.
- **Incremental NLP extraction caching (#24):** Introduced `IncrementalNotesExtractor` caching decisions and action items by transcript segment UUID, replacing $O(N)$ full-meeting text re-scans with $O(1)$ lookups on segment arrival.
- **Process-isolated scratch temp directories (#19):** Audio scratch files are now namespaced under `tmp_audio/pid_<PID>/` with 0700/0600 POSIX permissions. Orphan cleanup verifies process liveness (`kill(pid, 0)`), preventing secondary instances or self-tests from sweeping live recording audio.
- **Vocabulary seeding metadata flag (#23):** SQLite schema now includes persistent `metadata` key-value table (`user_version = 4`), recording initial lexicon setup so clearing dictionary terms never resurrects defaults on relaunch.
- **Automated bundle assembly in CI (#21):** CI workflow now runs `./assemble_app.sh`, validating release binary assembly, code signing, and bundle invariant self-tests on macOS 15 runners.

### Changed
- **Unified off-main export generator (#20):** Meeting Studio Copy, Studio Export, and History Export share a single document generator (`MeetingSession.exportMarkdown`); database queries and file writes execute asynchronously off the main actor; export filenames append 8-character session UUID slugs (`echo_meeting_<timestamp>_<slug>.md`) preventing same-second file collisions.
- **Clean-start documentation (#22):** Documented fresh-clone SwiftPM build instructions, engine path defaults overrides (`echo.runnerPath`), and macOS permission guidelines in `README.md`.

### Fixed
- **Dictation focus validation before injection (#4):** Target application bundle ID is captured when dictation begins. If the user changes active windows during inference, text is safely diverted to the clipboard with an informative HUD alert, preventing private text delivery into unintended apps.
- **Inference backlog budget bounding (#7):** Enforces a maximum pending queue budget (120s / 3.84MB PCM) in `TranscriptionService`, rejecting excessive submissions with typed `queueOverloaded` error to prevent unbounded memory growth.
- **Truncated preview delivery guard (#9):** When final full-audio inference returns empty, Echo labels the fallback text with `[Partial]` and bounds its duration to the 12s preview window, preventing truncated text from appearing as a full-duration transcript.
- **AudioHub hardware retain serialization (#16):** Serialized microphone and system audio hardware start/stop transitions with mutex locks, ensuring concurrent retains wait for initialization and failed starts never leave orphaned positive retain counts.
- **Sample-accurate VAD silence accounting & voiced gating (#18):** `VoiceActivityDetector` now accumulates exact silent and voiced sample counts across variable callback chunk sizes, eliminating buffer-size timing jitter and discarding brief noise impulses.
- **Production smoke test bundle invariants (#21):** `--test` self-test now verifies `CFBundleIdentifier`, `CFBundleExecutable`, window style masks, and returns exit code 1 on failure.

## [1.4.2] - 2026-11-20

### Added
- **Dictation history deletion control (#13):** Added `Clear Dictation History…` menu item under Meeting History, allowing users to safely purge standalone dictation snippets not tied to a meeting session (`DatabaseManager.deleteStandaloneDictations()`).
- **Degraded storage visibility (#12):** Exposed `DatabaseManager.isUsingFallbackStorage` and `activeDatabasePath`, surfacing status and warnings when Echo is running on a temporary fallback database.

### Fixed
- **Atomic session and utterance transactions (#11):** Wrapped session metadata and utterance persistence in a single immediate SQLite transaction with typed Result, preventing orphaned utterances and partial saves.
- **Concurrent clipboard overwrite protection (#14):** Guarded clipboard snapshot restoration against changes in `NSPasteboard.changeCount`, preserving newer content copied by the user during the paste cascade.
- **Emoji grapheme cluster typing (#15):** `SystemEventPoster.typeUnicodeString` now iterates full extended grapheme clusters rather than isolated UTF-16 code units, preventing emoji surrogate pair splitting and accurately reporting event failures.
- **Timeline capture-boundary timestamps (#10):** VAD now records exact audio boundary onset timestamps when speech starts, preserving chronologically ordered transcript segments in session timelines even under uneven inference latencies.
- **Single-pass system audio conversion (#17):** Decodes and resamples ScreenCaptureKit audio once per callback, sharing the converted 16 kHz buffer with VU meters and VAD while resetting stateful converter filters across session boundaries.

## [1.4.1] - 2026-11-19

### Fixed
- **Meeting finalization & transcript drain:** Audio and transcript finalization waits for accepted speech segments to finish processing before releasing resources. Meeting Studio and menu bar indicate when transcript is being finalized, including during a normal quit.
- **Speech engine readiness & error surfaces:** Validates local speech executable before recording starts and surfaces per-segment transcription errors during capture rather than silently dropping audio.
- **Transactional SQLite migrations:** Migrations commit schema changes atomically with their version marker; rolls back failed migrations and reports startup schema mismatches.
- **Transition serialization:** Added transition locks to prevent duplicate session allocation on rapid start/stop toggles.

## [1.4.0] - 2026-11-19

### Added
- **Meeting History menu & session export (`DATA-02`, `UX-05`):** The menu bar now has a Meeting History submenu listing the 8 most recent sessions with **Copy Transcript**, **Export Markdown File…**, and **Delete Session…** actions, plus a **Delete Empty Sessions** retention command. Deleting a session cascades to its utterances. Added `DatabaseManager.fetchSession(id:)` and `AppCoordinator.exportSession(id:)`.
- **Configurable Fermion device (`BUILD-04`):** Added `EchoSettings.resolveFermionDevice()` supporting `defaults write com.ragavij.echo echo.fermionDevice <cpu|mps|mlx>` and `ECHO_FERMION_DEVICE` overrides.

### Changed
- **Off-main SQLite persistence (`DATA-02`):** Live writes from transcription and dictation now go through the database's serial utility queue (`saveSessionAndUtteranceAsync`), so SQLite I/O no longer blocks the main actor. Session metadata and its utterance are persisted in one queue hop.
- **Schema migrations and retention (`DATA-02`):** `PRAGMA user_version` now tracks a v2 migration that adds `idx_sessions_start` for history queries. Prepare/step failures route through a single `reportError` path and surface through `onError` instead of being print-only.
- **Intrinsic HUD width measurement (`UX-03`):** Dynamic pill HUD width now calculates typographic dimensions via `(text as NSString).size(withAttributes:)` rather than estimating character count multipliers. Measured widths are quantized into 30pt buckets with an expanded 720pt cap to prevent truncation with wide glyphs, emoji, and CJK text.
- **Export menu behavior (`UX-05`):** Renamed menu action to "Export Current Session to Markdown…", guarded against empty/nil active sessions, and surface informational alert when attempting to export without an active transcript.

### Fixed
- **Word-boundary notes extraction (`UX-06`):** Decision and action item extraction in `MeetingNotesExtractor` now precompiles `NSRegularExpression`s with `\b` word boundaries and sorts triggers by length descending, preventing substring false positives (e.g. `"unapproved"`, `"disagreed"`). Added pre- and post-trigger negation filtering and passive-voice context preservation.
- **Empty session rows (`DATA-03`):** Launch no longer creates and persists an empty "Echo Speech Stream" session. The transient stream is created lazily on the first dictated or transcribed utterance, and empty/stale open sessions left by older builds are pruned at startup.
- **Non-destructive clipboard injection (`INJ-03`):** Accessibility injection now runs before any clipboard write, so a successful AX insert leaves the user's clipboard untouched. When the paste or typing fallbacks are needed, the full pasteboard contents are snapshotted and restored after success (`restorePreviousClipboard` now defaults to `true`). If every fallback fails, the transcript stays on the clipboard for a manual paste.
- **Global shortcuts double-firing (`INJ-05`):** The `⇧⌘E/D/C/R` chords are now owned by the global event monitor when Echo is in the background and by the menu key equivalents when Echo is frontmost. Previously both paths ran while the app was focused, so `⇧⌘D` and `⇧⌘R` started and immediately stopped.
- **Double SwiftUI invalidation (`CORE-02`):** Removed the last manual `objectWillChange.send()` in `MeetingCoordinator.stopSession()`; the `@Published` assignment already notifies observers.

### Removed
- **Stale AppleEvents declaration (`BUILD-05`):** Dropped `NSAppleEventsUsageDescription` from `Info.plist` now that the AppleScript fallback is gone.

---

## [1.3.1] - 2026-11-18

### Fixed & Hardened
- **Meter throttling & re-render isolation (`UX-02`):** Audio levels are isolated inside a dedicated `MeetingAudioLevels` observable object consumed exclusively by `LiveAudioMetersCluster`. The meeting studio transcript timeline, decisions, action items, and search views no longer re-evaluate on audio ticks.
- **Graceful shutdown & crash cleanup (`UX-04`):** Wired `NSApplicationDelegate.applicationWillTerminate` through `AppCoordinator.shutdownGracefully()` to stop active dictation, record `endTime` on open meeting sessions, flush SQLite WAL checkpoints, and release CoreAudio resources cleanly.
- **Secure temporary audio sandbox (`SEC-01`):** All intermediate audio PCM/WAV slices are restricted to `Application Support/Echo/tmp_audio` created with `0700` POSIX directory permissions and `0600` file permissions. Stale or orphaned `.wav` files are swept on launch and termination.
- **Global menu shortcuts (`INJ-02`):** Registered global `NSEvent` key monitoring for `⇧⌘E` (Meeting Studio), `⇧⌘D` (Dictation Toggle), `⇧⌘C` (Copy Last Dictation), and `⇧⌘R` (Meeting Recording), making them functional across all applications when Accessibility is granted.
- **Injection cascade & clipboard preservation (`INJ-03`, `SEC-02`):** Prioritized synthetic Cmd+V paste ahead of typing in the default cascade for instant, atomic insertion. Added optional non-destructive clipboard restoration (`restorePreviousClipboard`). Removed the AppleScript fallback, eliminating AppleEvents / Automation consent prompts.
- **Dead code removal (`BUILD-03`):** Removed unused prototype `PhononClient.swift`, stripped orphaned `BenchmarkResult`, and mapped process failures to descriptive `PhononClientError.processError`.
- **Documentation synchronization (`DOC-01`):** Harmonized README, ARCHITECTURE, and ROADMAP with actual codebase behavior (status bar level, hotkey behaviors, and 3-tier cascade).

## [1.3.0] - 2026-11-18

### Changed
- **Shared audio hub (`AUD-02`, `AUD-03`):** Dictation and meeting capture now share one `AudioEngineManager` through a reference-counted `AudioHub` instead of opening two taps on the same microphone. Buffers and meters fan out to multiple observers, so one consumer can no longer silently replace another.
- **Bounded transcription queue (`ENG-02`, `AUD-05`):** Meeting segments are transcribed through `TranscriptionService` with a single in-flight engine process (configurable) instead of one unbounded `fermion` process per VAD segment. `stopSession()` now waits (up to 5 s) for the queue to drain before writing `endTime`, so the final utterance is included in the session and export.
- **VAD pre-roll (`AUD-04`):** The detector keeps a configurable 300 ms pre-roll buffer and prepends it when speech starts, preventing clipped word onsets. Segment callbacks are now delivered synchronously so shutdown can observe the final segment.
- **Native "Graphite Frost" interface:** Replaced the black/brass/lavender theme with a neutral frosted graphite palette, a cool frost-blue primary accent, and a sea-glass secondary accent. Typography now uses SF Pro with monospaced digits only where telemetry benefits from them.
- **Meeting Studio redesign:** The window now uses real `NSVisualEffectView` vibrancy with a dark appearance, hidden titlebar, autosaved frame, and a unified toolbar-style header showing the session title, recording state, input meters, word memory, and record control. The accessibility notice is a quiet inline banner instead of an amber warning strip.
- **Transcript & Notes:** Transcript rows use native list spacing with speaker avatars, hover-to-copy, and subtle selection; the notes inspector has frosted cards, action-item progress (`2/4`), and a pinned accent export button.
- **HUD & menu bar:** The floating pill shares the graphite glass treatment with the frost-blue waveform. The menu-bar item uses SF Symbols for idle, dictating, and recording states, and menu copy was shortened to match macOS conventions.
- **App icon:** Replaced the old icon with the elk artwork, rebuilt on Apple's 824pt squircle grid with a soft dock shadow and hairline rim. The source, 1024px master, iconset, and regeneration scripts now live in the repo.
- **Developer tooling:** Debug builds accept `Echo --snapshot <directory>` to render PNGs of the studio and HUD, and Xcode `#Preview`s cover both surfaces for design iteration.
- **Reproducible build pipeline (`BUILD-01`):** Added version-controlled `Info.plist` and `assemble_app.sh` script for clean, reproducible release bundling and signing.

### Fixed
- **System-audio VU meter & capture error notifications (`AUD-06`):** ScreenCaptureKit sample buffers are now decoded to canonical 16 kHz Float32 PCM using `AudioBufferConverter.pcmBuffer` and `calculateRMS` rather than assuming raw Int16. Capture errors trigger `onCaptureFailed` and fan out through `AudioHub.addErrorObserver`.
- **Word-memory regex caching & cascade elimination (`LEX-01`):** Vocabulary patterns are precompiled on database load and cached in memory. Replacements use single-pass non-overlapping range matches to prevent cascading replacements and insert text directly to preserve `$`, `\`, and `&` without regex template corruption.
- **SQLite schema hardening & lifecycle management (`DATA-02`):** Configured 3-second busy timeout (`PRAGMA busy_timeout = 3000; sqlite3_busy_timeout`), enforced foreign key constraints (`PRAGMA foreign_keys = ON`), added `ON DELETE CASCADE` from utterances to sessions, implemented `user_version` schema migration tracking, added `deleteSession()`, WAL checkpointing, and background `dbQueue` async methods.
- **Product model separation & session restore (`DATA-01`):** Startup no longer resurrects closed sessions (`endTime != nil`) as active recording streams. Quick dictations while not in a meeting are preserved in the standalone SQLite dictations log rather than polluting meeting sessions.
- **Concurrency hardening (`CORE-01`):** Added lock-synchronized callback closures in `SystemAudioCapture`, `AudioEngineManager`, and `MeetingCoordinator` to prevent cross-queue races; marked `WordMemoryState` with `@MainActor`.
- **Automation TCC declaration (`SEC-02`, superseded):** Added `NSAppleEventsUsageDescription` in `Info.plist` for the AppleScript paste fallback. The fallback and the declaration were both removed in 1.3.1/Unreleased.
- **Safe SQLite database fallback:** Added graceful `NSTemporaryDirectory()` fallback in `DatabaseManager` ensuring tables are created and operations proceed even under restricted sandbox permissions.
- **Accessibility injection safety (`CORE-03`):** Guarded `focusedElement` with `CFGetTypeID` against unexpected CFTypes before casting to `AXUIElement`.
- **Eliminated double SwiftUI invalidation (`CORE-02`):** Removed redundant manual `objectWillChange.send()` calls when mutating `@Published` properties.

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
