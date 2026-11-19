# Echo — Code Review: Remaining Improvements

**Reviewed:** 2026-11-17 · **Last re-review:** 2026-11-19 · **Baseline commit:** `e250a3a` · **P0 fixed through:** `78dbd4a` · **Latest reviewed:** `bce471d` (v1.3.1) · **Scope:** `Sources/Echo` (33 files, ~6.8k LOC), `Tests/EchoTests` (13 suites), build scripts, docs

This document captures the findings that were **not** addressed in `e250a3a`. All four P0 items have since been fixed; their rationale is kept below so the backlog stays self-contained. Each item has an ID so it can be referenced from commits and issues.

This revision audits the 1.3.0/1.3.1 work (`dd92480`…`bce471d`) line by line. Most of the P1/P2 backlog is now genuinely resolved. Seven statuses were downgraded to **partially fixed** because the shipped change does not fully match the claim, and four new findings were added: `INJ-05`, `UX-06`, `DATA-03`, and `BUILD-05`. On 2026-11-19, `INJ-03`, `INJ-05`, `CORE-02`, `BUILD-05`, and `DOC-01` were fixed with regression coverage (98 tests now); `UX-06` and `DATA-03` remain open.

> Severity is about user-visible risk, not effort:
> **P0** = broken or unsafe today · **P1** = architectural debt with real failure modes · **P2** = UX/quality problems · **P3** = build, security, docs, hygiene.

---

## At a glance

| ID | Severity | Area | Finding | Status |
| :--- | :--- | :--- | :--- | :--- |
| AUD-01 | P0 | Performance | Partial transcription re-decodes the entire recording every 650 ms (O(n²), unbounded memory) | ✅ Fixed |
| ENG-01 | P0 | Reliability | Process runner can deadlock, has no timeout, and blocks a cooperative thread | ✅ Fixed |
| QLT-01 | P0 | Testing | `Tests/` is empty; harnesses are root scripts and `--test` always prints PASSED | ✅ Fixed |
| CFG-01 | P0 | Portability | Hardcoded `/Users/ragavij/...` paths for the engine, DB fallback, and export folder | ✅ Fixed |
| AUD-02 | P1 | Architecture | Two independent `AVAudioEngine`s contend for the microphone | ✅ Fixed |
| AUD-03 | P1 | Architecture | Audio/event callbacks are single-consumer closures and silently overwrite each other | ✅ Fixed |
| AUD-04 | P1 | Quality | VAD has no pre-roll, so word onsets are clipped | ✅ Fixed |
| AUD-05 | P1 | Correctness | `stopSession()` returns before flushed audio is transcribed | ✅ Fixed (5 s drain cap) |
| AUD-06 | P1 | Quality | System-audio meter assumes Int16; capture failures stop silently | ✅ Fixed |
| ENG-02 | P1 | Performance | Unbounded concurrent `fermion` processes per segment | ✅ Fixed |
| DATA-01 | P1 | Product model | Quick dictations are appended to the active meeting; startup restores yesterday's session | ✅ Fixed |
| DATA-02 | P1 | Storage | SQLite runs on the main thread; no migrations, busy timeout, foreign keys, or history UI | 🟡 Partial |
| CORE-01 | P1 | Concurrency | Pervasive `@unchecked Sendable`; no strict-concurrency checking | 🟡 Partial |
| CORE-02 | P1 | SwiftUI | `objectWillChange.send()` before mutating `@Published` causes double invalidation | ✅ Fixed |
| CORE-03 | P1 | Safety | Force-cast `focusedElement as! AXUIElement` in the injection path | ✅ Fixed |
| LEX-01 | P1 | Text quality | Sanitizer can cascade, breaks on `$`/`\` replacements, ASCII-only boundaries, no regex cache | ✅ Fixed |
| INJ-01 | P2 | UX | Global `⌃ Control` hotkey fires on every Control shortcut; no cancel or speech gate | ✅ Fixed |
| INJ-02 | P2 | UX | Documented global shortcuts are menu key equivalents and only work when Echo is focused | ✅ Fixed |
| INJ-03 | P2 | UX | Typing is preferred over paste; user clipboard is wiped despite "non-destructive" docs | ✅ Fixed |
| INJ-04 | P2 | UX | No feedback when microphone or system-audio capture fails; `statusMessage` is never rendered | ✅ Fixed |
| INJ-05 | P2 | UX | Global shortcuts double-fire when Echo is focused (event monitor + menu key equivalent) | ✅ Fixed |
| UX-01 | P2 | UI | "Live AI Executive Notes" is hardcoded placeholder content | ✅ Fixed |
| UX-02 | P2 | Performance | Entire Studio view invalidates at audio rate (~43 Hz) | ✅ Fixed |
| UX-03 | P2 | UI | HUD width is guessed from character count; `NSScreen.main` is wrong on multi-monitor setups | 🟡 Partial (anchoring fixed) |
| UX-04 | P2 | Lifecycle | No graceful shutdown: audio not stopped, session `endTime` not written, temp files left behind | ✅ Fixed |
| SEC-01 | P2 | Privacy | Sensitive WAVs are written to world-readable `/tmp` and may survive crashes | ✅ Fixed |
| UX-05 | P2 | UX | "Export All Notes" exports only the active session | 🟡 Partial |
| UX-06 | P2 | UI quality | Heuristic notes extractor matches trigger substrings and over-extracts decisions/actions | 🆕 Open |
| SEC-02 | P3 | Permissions | AppleScript fallback triggers Automation TCC but the bundle lacks `NSAppleEventsUsageDescription` | ✅ Fixed |
| BUILD-01 | P3 | Reproducibility | `Info.plist` and bundle assembly are not in version control | ✅ Fixed |
| BUILD-02 | P3 | Distribution | `codesign --deep` guidance; no hardened runtime or notarization | Open |
| BUILD-03 | P3 | Cleanup | Dead code: `PhononClient`, `BenchmarkResult`, unused enum case, unused field | ✅ Fixed |
| BUILD-04 | P3 | Performance | `FERMION_DEVICE=cpu` contradicts documented Metal/MLX acceleration | Open |
| BUILD-05 | P3 | Cleanup | `NSAppleEventsUsageDescription` remains after AppleScript removal; changelog contradicts itself | ✅ Fixed |
| DATA-03 | P3 | Storage | Every launch persists a new empty "Echo Speech Stream" session; no retention/compaction | 🆕 Open |
| DOC-01 | P3 | Docs | README/ARCHITECTURE/ROADMAP/CHANGELOG disagree with the code | ✅ Fixed |
| REPO-01 | P3 | Hygiene | No formatter/linter config, `.DS_Store`, simulator scripts with absolute paths | Open |
| REPO-02 | P3 | Testing | `test_injection.swift` fails on a stale assertion (pre-existing) | ✅ Fixed |

## Already fixed

| Finding | Fix | Commit |
| :--- | :--- | :--- |
| Meeting VADs were never fed; ScreenCaptureKit audio never decoded | Mic + system audio now fan out through `AudioBufferConverter` into both VADs | `e250a3a` |
| `sqlite3_bind_text` used temporary pointers with `SQLITE_STATIC` | All binds use a `SQLITE_TRANSIENT` helper | `e250a3a` |
| Dictionary upsert returned a phantom UUID/frequency | Upsert reads the persisted row back | `e250a3a` |
| Hardcoded engine, database and export paths (CFG-01) | `EchoSettings` resolution + `~/.echo` DB fallback + configurable export folder | `5feeef0` |
| Process runner could deadlock, had no timeout, ignored cancellation (ENG-01) | Concurrent stdout/stderr drains, watchdog with SIGTERM→SIGKILL, cancellation propagation | `7af83c3` |
| Partial transcription re-decoded the whole recording every 650 ms (AUD-01) | Chunked PCM store, 12 s live window, idle-tick skip, 10 min cap | `c244222` |
| `Tests/` was empty and `--test` always reported success (QLT-01, REPO-02) | Swift Testing suite, CI workflow, hermetic harness fixes | `78dbd4a` |
| Two microphone engines; single-consumer audio callbacks (AUD-02/AUD-03) | Reference-counted `AudioHub` with token-addressed fan-out | `dd92480` |
| Clipped onsets; unbounded per-segment inference (AUD-04/AUD-05/ENG-02) | 300 ms VAD pre-roll, synchronous flush, `TranscriptionService` with FIFO + drain | `dd92480` |
| System meter read Int16 blindly; capture errors were silent (AUD-06) | Converted-buffer RMS + `onCaptureFailed` through `AudioHub` error observers | `6995879` |
| SQLite had no pragmas/migrations and ran on the caller thread (DATA-02, partial) | WAL, busy timeout, foreign keys + cascade, `user_version`, async wrappers | `6995879` |
| Word-memory cascade, template corruption, recompilation (LEX-01) | Sorted precompiled regexes, non-overlapping single pass, literal insertion | `6995879` |
| Control chord collisions and HUD screen selection (INJ-01, UX-03 partial) | Esc-to-cancel, chord filter, discard button, mouse-screen anchoring | `441dc6d` |
| Hardcoded "AI" notes (UX-01) | `MeetingNotesExtractor` derives decisions/action items from the transcript | `4b824d7` |
| Silent mic failures and invisible status (INJ-04) | Permission request, error banners, live `statusMessage`, AX refresh on activate | `c5f30d3` |
| Studio audio-rate invalidation; no shutdown; `/tmp` audio; menu-only shortcuts (UX-02, UX-04, SEC-01, INJ-02) | Isolated meters, `shutdownGracefully`, 0700/0600 temp dir, global key monitor | `56014ea` |
| Dead `PhononClient`, `BenchmarkResult`, stale process error | Deleted prototype, mapped failures to `processError` | `56014ea` |
| Shortcut double-fire, last manual invalidation, stale AppleEvents key, doc drift (INJ-05, CORE-02, BUILD-05, DOC-01) | Global monitor owns background chords; menu owns focused chords; removed manual send; plist/changelog/docs re-synced | working tree, 2026-11-19 |
| Clipboard wiped during injection, even after AX success (INJ-03) | AX runs before clipboard writes; full pasteboard snapshot restored after successful paste/typing; transcript retained only when every fallback fails | working tree, 2026-11-19 |

---

## P0 — Fixed first (kept for reference)

### AUD-01 · Partial transcription re-decodes the whole recording

**Status:** ✅ Fixed in `c244222` (`perf(dictation)`).

**Where:** `Sources/Echo/AppCoordinator.swift:176-212` (snapshot at `:179-181`, timer at `:154-159`)

Every 650 ms a new `fermion` process is spawned and given **all audio captured so far**, not just the new audio. At 60 s of speech each partial decodes 60 s of audio; `isTranscribingPartial` only prevents overlap, so partials get sparser and the CPU stays pinned. The buffer also grows without bound (~115 MB/hour) and is copied on append while the audio thread holds the lock.

**Fix:**
- Transcribe a bounded window — e.g. keep the last 10–15 s plus a committed prefix, and replace committed audio once a stable partial is accepted.
- Store PCM in a ring buffer / `[UInt8]` chunk list instead of `Data` + repeated `append`.
- Consider a streaming decoder (or the persistent `PhononClient` server below) so partials are incremental rather than full re-decodes.
- Add a cap that forces `finishDictation()` for very long sessions.

### ENG-01 · Process runner can deadlock and has no timeout

**Status:** ✅ Fixed in `7af83c3` (`fix(engine)`).

**Where:** `Sources/Echo/Engine/PhononProcessRunner.swift:14-42`

`waitUntilExit()` is called before the pipes are drained (`:28`). If `fermion` writes more than a pipe buffer to stdout/stderr, the child blocks on write while the parent blocks on exit — a deadlock. There is no timeout, and `Task.cancel()` cannot terminate the child, so a wedged process leaves the HUD stuck on "Finalizing…". `waitUntilExit()` also blocks a cooperative-pool thread.

**Fix:**
```swift
try process.run()
// Drain concurrently, then await termination with a watchdog:
let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile() // on a background queue
// or use terminationHandler + async continuation
```
- Add a configurable deadline (e.g. 30 s) and `process.terminate()` / `kill` on expiry or cancellation.
- Use `withTaskCancellationHandler` so the HUD can recover.
- Sanitize stdout: `fermion` may print progress lines that would end up in the transcript.

### QLT-01 · The test suite is empty

**Status:** ✅ Fixed in `78dbd4a` (`test`).

**Where:** `Package.swift:20-24`, `Tests/` (empty), `test_*.swift` at the repo root, `Sources/Echo/main.swift:12-45`

- `swift test` runs nothing; the declared `EchoTests` target produces the build warning about missing sources.
- Root harnesses use `assert()`, which is compiled out under `-O` (release builds).
- `--test` prints "PASSED (100% Operational)" unconditionally and touches singleton state rather than asserting.
- `test_injection.swift` writes into the **production** database via `DatabaseManager.shared`.

**Fix:**
- Move the harnesses into `Tests/EchoTests` as XCTest / Swift Testing cases.
- Inject `DatabaseManager(customPath: temp)` everywhere (already supported).
- Add coverage for the pure logic that currently has none: hotkey state machine, VAD segmentation and pre-roll, sentence formatting, word-memory replacement, Markdown export, audio conversion, and the injection cascade.
- Run `swift test` in CI on push/PR.

### CFG-01 · Hardcoded machine-specific paths

**Status:** ✅ Fixed in `5feeef0` (`fix(config)`).

**Where:**
- `Sources/Echo/Engine/PhononProcessRunner.swift:6` — engine binary
- `Sources/Echo/Storage/DatabaseManager.swift:61-62` — DB fallback
- `Sources/Echo/AppCoordinator.swift:340-345` — export directory

**Impact:** on any other Mac, transcription fails, the database falls back into a nonexistent project folder, and export silently does nothing (`try?` + unconditional `print` of success).

**Fix:**
- Bundle the engine or resolve it via `Bundle.main`, a user setting, or `PATH`; validate at launch and show a setup screen if missing.
- Fall back to `Application Support/Echo` (or the sandbox container) rather than the source tree.
- Export through `NSSavePanel` or a configured Obsidian vault path; surface write errors.

---

## P1 — Architecture and correctness

### AUD-02 · Two audio engines on one microphone

**Status:** ✅ Fixed. `AudioHub` owns the single `AudioEngineManager`; dictation and meetings retain/release the same engine.

**Where:** `Sources/Echo/AppCoordinator.swift:42`, `Sources/Echo/Audio/DualChannelCoordinator.swift:41-46`

Dictation owns one `AudioEngineManager`; the meeting coordinator creates another. During a meeting, push-to-talk opens a second `AVAudioEngine` and tap on the same input device — duplicated capture, conversion, CPU, and possible device contention.

**Fix:** one `AudioHub` owning a single engine, with dictation and both meeting VADs as subscribers. This also removes the need for separate conversion paths.

### AUD-03 · Single-consumer callback closures

**Status:** ✅ Fixed. `AudioHub` fans buffers and levels out to token-addressed observers.

**Where:** `Sources/Echo/Audio/AudioEngineManager.swift:11-12`, `Sources/Echo/Audio/SystemAudioCapture.swift:10-11`, `Sources/Echo/Audio/DualChannelCoordinator.swift:51-69`

`onAudioBuffer`, `onVolumeLevel`, etc. are one closure each. A second consumer silently replaces the first — exactly how the VAD wiring stayed invisible for so long.

**Fix:** a small multicast fan-out (`AsyncStream`, observer array, or Combine subject) with removal tokens, and tests that assert all subscribers receive data.

### AUD-04 · VAD clips word onsets

**Status:** ✅ Fixed. `VoiceActivityDetector` keeps a 300 ms pre-roll (`preRollSeconds`) and prepends it when speech starts.

**Where:** `Sources/Echo/Audio/VoiceActivityDetector.swift:39-64`

Audio is only buffered after energy crosses the threshold, so the first phoneme of every utterance is usually lost — one of the most visible causes of "it misheard the beginning".

**Fix:** keep a 250–300 ms pre-roll ring buffer and prepend it when speech starts. Consider an adaptive noise floor (or a spectral VAD) for noisy rooms, and make `energyThreshold` / `silenceThresholdSeconds` configurable (already on the roadmap).

### AUD-05 · `stopSession()` races the final transcription

**Status:** ✅ Fixed (`dd92480`). `flush()` now delivers the final segment synchronously, `TranscriptionService` tracks every submission, and `stopSession()` waits for the queue to drain before writing `endTime`. The shared FIFO service also serializes the two VADs.

**Residual:** the drain timeout is 5 s (`MeetingCoordinator.swift:245`). A slow segment past that cap is appended after `endTime`; it still reaches SQLite, but it can miss the in-memory/export snapshot. Consider surfacing the truncated drain or raising the cap for the final segment.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:233-258`, `Sources/Echo/Audio/VoiceActivityDetector.swift:87-98`

The original race: `flush()` dispatched the segment callback asynchronously, then `stopSession()` immediately wrote `endTime` and returned. Two VADs also produced segments whose transcription order was not guaranteed.

**Fix:** track in-flight transcription tasks, await them in `stopSession()` (with a timeout), and serialize transcription through an ordered queue.

### AUD-06 · System-audio meter assumes Int16; capture failures are silent

**Status:** ✅ Fixed (`6995879`). ScreenCaptureKit sample buffers are decoded through `AudioBufferConverter.pcmBuffer` and `calculateRMS`; `didStopWithError` invokes `onCaptureFailed` and fans out via `AudioHub.addErrorObserver`.

**Residual:** `didStopWithError` clears `isCapturing` but leaves the failed `SCStream` in `SystemAudioCapture.stream` (`SystemAudioCapture.swift:106-112`), and `AudioHub` keeps its system-audio retain count. A dropped stream therefore cannot be restarted until the owner releases and re-retains, and there is no auto-restart. Minor, but the Studio banner is the only recovery path.

**Where:** `Sources/Echo/Audio/SystemAudioCapture.swift:79-98`, `:100-104`

The VU meter reinterprets ScreenCaptureKit samples as `Int16` without checking the stream format; those buffers are commonly `Float32`, so the meter can read nonsense. `didStopWithError` clears the flag but notifies nobody, so a dropped stream looks like a healthy recording.

**Fix:** compute the meter from the already-converted 16 kHz buffer (reuse `AudioBufferConverter`), and expose a callback/error state that the Studio can display and optionally auto-restart.

### ENG-02 · Unbounded concurrent transcription processes

**Status:** ✅ Fixed. Handled via bounded `TranscriptionService` with serialization and backpressure.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:89-103`, `:173-211`

Each VAD completion spawns `Task { await processSpeechSegment(...) }`, which launches a new `fermion` process. Two VADs plus push-to-talk can run several heavy inference processes at once, and a long meeting can queue faster than it drains.

**Fix:** a bounded `TranscriptionService` actor (serial queue or max 1–2 in flight) with back-pressure; ideally one persistent server process (wire up the existing `PhononClient` or keep `fermion` running on stdin/stdout) so model load isn't paid per utterance.

### DATA-01 · Dictation and meetings share one timeline

**Status:** ✅ Fixed (`6995879`). Closed sessions (`endTime != nil`) are not revived as active recording streams on startup; standalone quick dictations are saved to the SQLite dictation log with `sessionId == nil` (`AppCoordinator.swift:358-372`) and no longer require an active meeting. A quick dictation during a meeting is intentionally appended to that meeting.

**Residual:** when the last session is closed, startup creates and persists a brand-new empty "Echo Speech Stream" session (`MeetingCoordinator.swift:73-77`). See `DATA-03`.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:33-42`, `:104-132`; `Sources/Echo/AppCoordinator.swift:262`

Startup restores the most recent session as `activeSession`, so today's quick dictations are appended to yesterday's meeting. "Start Meeting" replaces `activeSession`, hiding earlier dictations from the UI even though they are in SQLite. There is no session history browser.

**Fix:** separate "dictation log" from "meeting session" (different streams/views), start sessions explicitly, and add a sidebar of past sessions with search (roadmap v1.1/v2.0).

### DATA-02 · SQLite lifecycle and schema hardening

**Status:** 🟡 **Partially fixed** (`6995879`). Configured `PRAGMA busy_timeout = 3000` + `sqlite3_busy_timeout`, `PRAGMA foreign_keys = ON`, `FOREIGN KEY ... ON DELETE CASCADE` on utterances, `PRAGMA user_version` migrations, `deleteSession()` with cascading cleanup, `checkpointWAL()`, and dedicated `dbQueue` async wrappers.

**What remains:**
- The async wrappers are **unused in production**. The live path still calls synchronous `saveSession`/`saveUtterance` from `appendTranscribedSegment` on `MainActor` (`MeetingCoordinator.swift:167-177`), so every utterance blocks the main thread on SQLite I/O. Either use `saveSessionAsync`/`saveUtteranceAsync` there or move the coordinator's persistence to a storage actor.
- The migration runner only knows schema v1; there is no v2 hook or migration test.
- No retention/compaction: `deleteSession` is never called from the app, and WAL growth is only checkpointed (not bounded). There is still no session-history/delete UI.
- Central SQLite error handling is still `print`-only; failures are not surfaced.

**Where:** `Sources/Echo/Storage/DatabaseManager.swift` (all public methods)

- Every read/write runs synchronously on the main actor when called from SwiftUI/coordinators.
- No `user_version` / migration path; schema changes will require manual handling.
- No `busy_timeout`, no `foreign_keys`, no `ON DELETE CASCADE` from `utterances` to `sessions`.
- `idx_dictionary_pattern` duplicates the index created by `UNIQUE(raw_pattern)`.
- No session deletion / retention / compaction; WAL can grow indefinitely.
- Failures (`sqlite3_prepare_v2`, `sqlite3_step`) are still ignored outside the dictionary upsert.

**Fix:** move storage behind an actor or serial queue, add a versioned migration runner, `PRAGMA busy_timeout = 3000`, `PRAGMA foreign_keys = ON`, a `sessions → utterances` cascade, and centralized SQLite error handling/logging.

### CORE-01 · `@unchecked Sendable` everywhere

**Status:** 🟡 **Partially fixed** (`6995879`, `56014ea`). Synchronized cross-thread callback closures with locks in `SystemAudioCapture`, `AudioEngineManager`, and `MeetingCoordinator`; marked UI state `WordMemoryState` with `@MainActor`; added `CaptureFlag` for the audio-thread read in `AppCoordinator`. These are real improvements and remove several concrete races.

**What remains:** the package still declares `swiftLanguageModes: [.v5]` and 22 `@unchecked Sendable` declarations. Several remain unsynchronized, e.g. `HotkeyManager`'s mutable callback/state properties (monitor threads read them while `AppCoordinator` writes from `MainActor`) and `MeetingCoordinator`'s `@Published activeSession` accessed from async tasks. Strict concurrency is still the way to validate the remaining annotations. Lower severity now, but the finding is not closed.

**Where:** `DatabaseManager`, `WordMemoryEngine`, `WordMemoryState`, `MeetingCoordinator`, `AudioEngineManager`, `DualChannelCoordinator`, `SystemAudioCapture`, `HotkeyManager`, `TextInjector`, `PhononProcessRunner`, `PhononClient`

The annotation is used to silence the compiler rather than to document a real guarantee. AppKit/SwiftUI types (panels, windows) are callable from any thread, and mutable state crosses audio/main/SCK queues — for example, the audio callback closures are invoked on the audio thread while callers reassign them from the main actor.

**Fix:** adopt Swift 6 language mode / strict concurrency. Mark UI types `@MainActor`, make storage and the transcription pipeline actors, and use `@Sendable` only where the closure truly is. Expect this to surface several real races.

### CORE-02 · Double SwiftUI invalidation

**Status:** ✅ Fixed (2026-11-19). The remaining manual send in `stopSession()` was removed; assigning the `@Published` `activeSession` is now the only invalidation. `grep objectWillChange Sources` is empty apart from the explanatory comment.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:254` (remaining); original sites were `:134`, `:156`, `:178`

Calling `objectWillChange.send()` before mutating an `@Published` property sends two change notifications and can render a half-updated state.

**Fix:** delete the remaining manual send; the `activeSession` assignment already publishes.

### CORE-03 · Force-cast on the accessibility element

**Status:** ✅ Fixed. Guarded with `CFGetTypeID(focusedElement) == AXUIElementGetTypeID()` before casting.

**Where:** `Sources/Echo/Injection/TextInjector.swift:280-284`

`focusedElement as! AXUIElement` will crash if the AX server returns an unexpected CFType. A misbehaving or malicious app should not be able to crash Echo.

**Fix:** `guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return false }`.

### LEX-01 · Word-memory replacement edge cases

**Status:** ✅ Fixed. Regexes are precompiled on load and cached in memory; `sanitize()` operates in a single pass with non-overlapping range matches (preventing cascades); direct string insertion preserves `$`, `\`, and `&` literally.

**Where:** `Sources/Echo/Storage/WordMemoryEngine.swift:57-90`

- Replacements are applied sequentially, so one entry's output can be matched again by a later entry (cascading, order-dependent output).
- `withTemplate:` interprets `$1`, `\` and `&` in the replacement; a user entry like `C:\path` or `$5` corrupts text.
- `\b` is ASCII-oriented; it will not behave correctly for the multilingual roadmap.
- A fresh `NSRegularExpression` is compiled for every entry on every call (live partials included).

**Fix:** build one alternation regex (longest pattern first) and replace with a block (`matches` + manual substitution) or `NSRegularExpression.escapedTemplate(for:)`; cache compiled patterns and invalidate on dictionary changes; consider Unicode-aware tokenization for non-Latin scripts.

---

## P2 — UX and product behaviour

### INJ-01 · Global Control key is too broad

**Status:** ✅ Fixed. Added `Esc` key monitor to cancel dictation, discard audio, and dismiss HUD immediately without injecting. Added chord filter: simultaneous modifiers (Command/Option/Shift) or key presses while Control is held down (e.g. `Ctrl+C`, `Ctrl+Space`) mark session as chorded and abort recording. Added dedicated discard button (✕) to floating pill.

**Where:** `Sources/Echo/Injection/HotkeyManager.swift`, `Sources/Echo/AppCoordinator.swift`

Observing `.control` in `.flagsChanged` means **every** `Ctrl+C`, `Ctrl+Space`, emacs binding, Mission Control chord, etc. starts dictation. A short tap with background noise can inject unexpected text, and there is no way to cancel a mistaken dictation (no Esc handling, no "discard" button).

**Fix:** use a dedicated trigger (Fn/Globe, a right-side modifier, or a Carbon-registered chord), make it configurable (roadmap v1.1), require a minimum speech energy/duration before injecting, and add Esc-to-cancel. Document the double-tap windows from one constant (code uses 350 ms hold / 260 ms double-tap; docs say 380 ms).

### INJ-02 · "Global" shortcuts are not global

**Status:** ✅ Fixed (`56014ea`). Added global `NSEvent` key monitoring in `HotkeyManager` for `⇧⌘E` (Meeting Studio), `⇧⌘D` (Dictation Toggle), `⇧⌘C` (Copy Last Dictation), and `⇧⌘R` (Meeting Recording), wired to `AppCoordinator`.

**Regression:** the same four shortcuts are still `NSMenuItem.keyEquivalent`s in `MenuBarManager` (`:140-180`). When Echo is frontmost, the local event monitor and the menu key equivalent both run, so toggles fire twice. See `INJ-05`.

**Where:** `Sources/Echo/UI/MenuBarManager.swift:112-151` (original)

Originally, `⇧⌘E`, `⇧⌘D`, `⇧⌘C`, `⇧⌘R` were only `NSMenuItem.keyEquivalent`s. In an `.accessory` app they only fire while Echo or its menu is focused, although the README listed them as global shortcuts.

**Fix (applied):** a global `NSEvent` key-down monitor now handles them system-wide. Remove the duplicate focused-app path per `INJ-05`.

### INJ-03 · Injection order and clipboard behaviour

**Status:** ✅ Fixed (2026-11-19). The cascade is now AX → paste → typing, and the clipboard contract is non-destructive by default.

- `inject` runs `performAccessibilityInjection` **before** any clipboard write, so a successful AX insert never touches the pasteboard (`accessibilityInjectionLeavesClipboardUntouched`).
- `InjectionOptions.restorePreviousClipboard` defaults to `true`. When a clipboard-based fallback is required, the injector snapshots every pasteboard item (all types) and restores it after a successful paste (60 ms delay) or typing (immediate).
- An empty clipboard is snapshotted as `nil` and cleared again after success, rather than being left with the transcript.
- If both synthetic fallbacks fail, the transcript deliberately stays on the clipboard so the user can paste it manually.
- `ARCHITECTURE.md` and `README.md` now describe this contract instead of claiming the clipboard is never wiped.

**Where:** `Sources/Echo/Injection/TextInjector.swift`; `Tests/EchoTests/TextInjectorTests.swift`

**Tests:** `restoreClipboardPreservesOriginalContent`, `restoringDisabledLeavesTranscriptOnClipboard`, `accessibilityInjectionLeavesClipboardUntouched`, `failedFallbacksKeepTranscriptOnClipboard`, plus the empty-clipboard assertions in `pasteIsUsedWhenDirectTypingIsDisabled` / `longTranscriptSkipsDirectTyping`.

### INJ-04 · Silent audio failures; unused status surface

**Status:** ✅ Fixed. Added explicit `AVCaptureDevice` permission validation and request; wired `AudioHub.addErrorObserver` across `AppCoordinator` and `MeetingCoordinator`; rendered live `captureErrorBanner` and `microphoneBanner` in `MeetingStudioView`; rendered `statusMessage` live in Studio title bar and Menu Bar; and added automatic AX/mic permission refresh on `NSApplication.didBecomeActiveNotification`.

**Where:** `Sources/Echo/AppCoordinator.swift`, `Sources/Echo/Engine/MeetingCoordinator.swift`, `Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift`, `Sources/Echo/UI/MenuBarManager.swift`

`try? micEngine.startCapture()` swallows permission and device errors, so the HUD says "Listening" while capturing nothing. `statusMessage` is published but never rendered. The accessibility banner recomputes `AXIsProcessTrusted()` in `body`, so it doesn't refresh when permission changes.

**Fix:** request microphone access explicitly (`AVCaptureDevice.requestAccess(for: .audio)`), surface a state/banner for denied permission, remove or render `statusMessage`, and observe AX trust changes (notification/`Timer`/on-activate refresh).

### INJ-05 · Global shortcuts fire twice when Echo is focused

**Status:** ✅ Fixed (2026-11-19). The `⇧⌘E/D/C/R` handling moved out of `handleKeyDown` into `handleGlobalShortcut`, which only the global monitor calls. The local monitor still handles Esc/Control chords; while Echo is frontmost the menu key equivalents own the four chords, and while it is in the background the global monitor owns them. Regression test: `focusedAppShortcutsAreLeftToTheMenu`.

**Where:** `Sources/Echo/Injection/HotkeyManager.swift:52-58`, `:173-194`; `Sources/Echo/UI/MenuBarManager.swift:140-180`

The global `NSEvent` key monitor handles `⇧⌘E/D/C/R`, but the same chords remain `NSMenuItem.keyEquivalent`s. Local event monitors run before AppKit dispatches the event, so while the Meeting Studio (Echo) is frontmost both paths fire:

- `⇧⌘D` → `onToggleDictation` runs, then the menu item runs again: dictation starts and is immediately finished.
- `⇧⌘R` → meeting recording starts then stops.
- `⇧⌘E` → the studio is shown twice (mostly harmless).
- `⇧⌘C` → copies the last transcript twice (harmless).

The added test only calls `handleKeyDown` directly (`HotkeyManagerTests.swift:170-195`), so it cannot see the duplicate AppKit dispatch. A minimal AppKit harness (local `.keyDown` monitor + a `.command/.shift` menu key equivalent + a synthesized event) produced `monitor=1 menu=1`, confirming both paths run.

**Fix:** choose one owner per shortcut. Either remove the four local-monitor branches when `NSApp.isActive` (let the menu equivalents handle the focused case and the global monitor handle other apps), or drop the key equivalents and show the chord in the menu title. Add a note that global shortcuts require Accessibility permission, and cover the real dispatch path with a UI-level/manual check.

### UX-01 · Hardcoded "AI" notes

**Status:** ✅ Fixed (`4b824d7`). Created `MeetingNotesExtractor` with sentence analysis to derive decisions and action items from transcript utterances. Replaced hardcoded strings with live cards, empty-state guidance, and interactive item management.

**Caveat:** the extractor is a trigger-word heuristic, not an LLM, and its matching is currently too broad. See `UX-06`.

**Where:** `Sources/Echo/Engine/MeetingNotesExtractor.swift`, `Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift`

"Key Decisions" and "Action Items" are literal strings, including "Single binary unified app (saves 1.2 GB RAM)". The panel is labelled "LIVE AI EXECUTIVE NOTES".

**Fix:** generate them from the transcript (v1.1 local LLM), or label the cards as static placeholders until then.

### UX-02 · Studio re-renders at audio rate

**Status:** ✅ Fixed. Isolated audio levels inside `MeetingAudioLevels: ObservableObject` consumed only by `LiveAudioMetersCluster`. Audio level changes no longer trigger `MeetingCoordinator.objectWillChange`, eliminating all main-thread UI invalidations on the transcript list.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:82-90`, `Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift`

`micLevel` / `systemLevel` are `@Published` and updated ~43×/s, invalidating the whole studio (including the full transcript list) each frame.

**Fix:** throttle levels to ~10 Hz, isolate meters in their own `ObservableObject`/`Canvas`, and avoid observing them from the timeline subtree.

### UX-03 · HUD sizing and screen selection

**Status:** 🟡 **Partially fixed** (`441dc6d`). The pill now anchors to the display containing the mouse pointer (`FloatingPillPanel.swift:137-144`) instead of `NSScreen.main`, with `NSScreen.main` as fallback. This resolves the multi-monitor half of the finding.

**What remains:** width is still derived from character count (`:116-131`, `livePartial.count × 7.0`, `preview.count × 6.5`), merely quantized into 40 pt / 30 pt buckets. Wide glyphs, emoji, and CJK still mis-size, and the hard 640/560 caps can truncate.

**Where:** `Sources/Echo/UI/FloatingPillPanel.swift`

**Fix:** measure with `NSAttributedString.size()` or let `NSHostingView.fittingSize` drive the window width; keep the existing screen anchoring.

### UX-04 · No graceful shutdown / crash cleanup

**Status:** ✅ Fixed (`56014ea`). Created `EchoAppDelegate.applicationWillTerminate` and `AppCoordinator.shutdownGracefully()` to cancel active dictations, record `endTime` on open sessions, flush SQLite WAL checkpoints, stop all audio engines, and sweep temporary audio files. Synchronous cleanup (dictation cancel, mic stop, session write, WAL, sweep) runs before the app exits.

**Residual:** the meeting teardown is fired into an un-awaited `Task` (`AppCoordinator.swift:508-513`), so system-audio `stopCapture()` may not finish before `exit`. The temp sweep also runs immediately while in-flight transcriptions may still be reading their temp WAVs; `shutdownGracefully` does not await `TranscriptionService` drain. Low risk at termination, but do not reuse this function as a general "stop meeting" path.

**Where:** `Sources/Echo/main.swift`, `Sources/Echo/AppCoordinator.swift`

No `applicationWillTerminate`: recording is not stopped, the active session's `endTime` is not written, pending transcriptions are not awaited, and temp WAVs are not swept. A crash leaves files behind.

**Fix:** implement `applicationShouldTerminate` / `applicationWillTerminate` async shutdown, add a launch-time sweep of stale `echo_*.wav` files, and stop audio before exiting.

### SEC-01 · Sensitive audio in world-readable temp

**Status:** ✅ Fixed. Created `AudioTempDirectory` placing audio scratchpads in `Application Support/Echo/tmp_audio` with POSIX `0700` directory and `0600` file permissions. Stale files are automatically swept on launch and graceful shutdown.

**Where:** `Sources/Echo/AppCoordinator.swift:188-193`, `:243-248`, `Sources/Echo/Engine/MeetingCoordinator.swift:176`

Every partial and segment is written to `FileManager.default.temporaryDirectory` with default permissions. On macOS `/var/folders/...` is per-user, but the files are still readable by any process of the user and survive crashes.

**Fix:** use an app-support `Recordings/tmp` directory created with `0700`, write files with `0600`, delete with `defer`, and sweep on launch. Longer term, pipe audio to a persistent decoder to avoid disk entirely.

### UX-05 · Export scope is misleading

**Status:** 🟡 **Partially fixed** (`56014ea`). The menu item is now "Copy Notes as Markdown", failures surface an `NSAlert`, the export directory is configurable (`EchoSettings.exportDirectory`, 0700), and the Markdown is copied to the clipboard.

**What remains:**
- Scope is still `meetingCoordinator.activeSession` only; there is no session picker/history (`AppCoordinator.swift:465-484`).
- When `activeSession` is `nil`, it fabricates an empty session and writes an empty Markdown file.
- The label says "Copy" but the action also writes a file. Pick one behavior or label both.

**Where:** `Sources/Echo/AppCoordinator.swift:465-498`, `Sources/Echo/UI/MenuBarManager.swift:184-191`

**Fix:** rename to "Export Current Session…", add a session picker, and guard `activeSession == nil` before writing.

### UX-06 · Notes extraction over-matches

**Status:** 🆕 Open (introduced by `4b824d7`).

**Where:** `Sources/Echo/Engine/MeetingNotesExtractor.swift:16-72`, `:86-102`, `:121-137`; consumed from `MeetingStudioView.swift:99-107`

Triggers are matched with `String.range(of:)` and no word boundary, and the shortest trigger wins:

- `"approved"` matches inside `"unapproved"`; `"agreed"` inside `"disagreed"`.
- `"approved"` / `"we will"` are so broad that almost any sentence becomes a "decision" or "action item". Example: "The design was approved by legal" yields a decision of "By legal." (or the whole sentence when the tail is short).
- Matching stops at the first trigger, so `"we decided to approve X"` produces `"Approve X."` rather than preserving/removing the decision phrase intentionally.
- There is no cap, so a long meeting fills the cards with low-confidence items.

This is an acceptable v1 heuristic, but it should be labelled as such and hardened before it is presented as meeting intelligence.

**Fix:** use word-boundary matching (`NSRegularExpression` or tokenization), prefer longest triggers, require a minimum tail length/predicate, and cap the list (or add confidence/undo). Add negative tests (`"unapproved"`, `"disagreed"`).

---

## P3 — Build, security, docs, hygiene

### SEC-02 · AppleScript fallback vs. Automation permission

**Status:** ✅ Fixed (`56014ea`). Removed the AppleScript fallback completely. AX direct injection + universal synthetic `Cmd+V` (with `.maskCommand` isolation) handles the injection path without requiring AppleEvents / Automation consent.

**Cleanup (done 2026-11-19):** removed the now-unused `NSAppleEventsUsageDescription` from `Info.plist` and corrected the 1.3.0 changelog entry.

**Where:** `Sources/Echo/Injection/TextInjector.swift` (fallback removed); `Info.plist`

`NSAppleScript` ("System Events keystroke v") requires Automation consent. At the time of the original review the bundle had no `NSAppleEventsUsageDescription`, so the fallback could produce the exact "Echo would like to control System Events" prompt loop the changelog said was fixed.

**Fix (applied):** the AppleScript fallback was removed. AX + `CGEvent` is sufficient, and Echo no longer depends on Automation for core dictation. Remove the now-unused plist key per `BUILD-05`.

### BUILD-01 · Bundle assembly is not reproducible

**Status:** ✅ Fixed (`5ca20b2`). `Info.plist` is checked in at the repo root (not `Support/`), and `assemble_app.sh` builds release, stages the bundle, signs ad-hoc, verifies, and runs the self-test. `CFBundleShortVersionString`/`CFBundleVersion` are both 1.3.1.

**Residual:** the script still calls `codesign --deep` (`BUILD-02`), and the `--test` step exits 0 on the unconditional `PASSED` banner rather than asserting. Version is still duplicated between `Info.plist` and `CHANGELOG.md`; consider one source of truth (a `VERSION` file or `MARKETING_VERSION` stamping).

**Where:** `Package.swift`, `Info.plist`, `assemble_app.sh`, README "Compiling from Source"

**Fix (done):** check in the plist, add an assembly script, and keep one source of truth for the version.

### BUILD-02 · Signing and distribution

**Where:** README "Packaging & Code Signing"

`codesign --deep` is deprecated for signing and can hide missing inner signatures. Ad-hoc signing with an identifier-only designated requirement is fine for local development but not distributable.

**Fix:** sign inner-to-outer (`--force --options runtime --timestamp --sign "Developer ID Application: …"`), notarize with `notarytool`, and staple. Keep the documented ad-hoc recipe only for local dev, clearly labelled.

### BUILD-03 · Dead code

**Status:** ✅ Fixed. Deleted unused `PhononClient.swift`, removed unused `BenchmarkResult` struct, and mapped process failures to descriptive `PhononClientError.processError`.

- `Sources/Echo/Engine/PhononClient.swift` — a complete HTTP transcription client that nothing calls.
- `Sources/Echo/Engine/STTTypes.swift:11` — `BenchmarkResult` unused; `PhononClientError.invalidURL` unused.
- `Sources/Echo/Injection/HotkeyManager.swift:13` — `lastKeyUpTime` written but never read.
- `Sources/Echo/Engine/PhononProcessRunner.swift:38` — process failures are reported as `PhononClientError.serverError`, which is misleading.

**Decision:** either wire `PhononClient` to a persistent local server (recommended — fixes ENG-01/ENG-02 and model reload), or delete it. Rename the process error case.

### BUILD-04 · CPU vs. documented GPU acceleration

**Where:** `Sources/Echo/Engine/PhononProcessRunner.swift:19`

`FERMION_DEVICE=cpu` contradicts README/ARCHITECTURE claims of Metal/MLX acceleration. Either the claims or the setting are wrong.

**Fix:** benchmark `metal`/`mlx` vs `cpu`, default to the fastest reliable path, and expose it as a setting.

### BUILD-05 · Stale AppleEvents declaration and changelog contradiction

**Status:** ✅ Fixed (2026-11-19). `NSAppleEventsUsageDescription` was removed from the tracked `Info.plist` (`plutil -lint` clean). The 1.3.0 entry now describes the declaration as superseded, and the new `[Unreleased]` section records the removal.

**Where:** `Info.plist`; `CHANGELOG.md` (`Unreleased`, `1.3.0`); `assemble_app.sh`

**Note:** the ignored `Echo.app/Contents/Info.plist` still contains the old key until `assemble_app.sh` is run again; always rebuild the bundle from the checked-in plist.

### DATA-03 · Empty session row on every launch

**Status:** 🆕 Open.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:67-77`

When the most recent session is closed, initialization creates a fresh `"Echo Speech Stream"` session and immediately persists it. Nothing is recorded into it unless the user dictates, so every launch after a completed meeting leaves an empty session row (and the test suite encodes this behavior). Over time the session list fills with empty streams, and there is no cleanup (`deleteSession` is never called by the app).

**Fix:** create the transient stream lazily on the first utterance/partial rather than in `init`, or reuse a single per-day stream; add retention (e.g. delete empty or older-than-N-days sessions) before shipping a history browser.

### DOC-01 · Documentation drift

**Status:** ✅ Fixed (2026-11-19). The documentation was re-synchronized with the code:

- `ARCHITECTURE.md` — injection is now described as AX → paste → typing with the real 25 ms settle/Control behavior; the clipboard paragraph no longer claims it is never wiped; the engine section says CPU by default with `ECHO_FERMION_DEVICE` override.
- `README.md` — clipboard, Markdown export, CPU default, and the `⇧⌘` Accessibility caveat now match the implementation and menu labels.
- `ROADMAP.md` — removed the retired brass/Obsidian theme claim, the stale 30 ms/Option settling detail, and the old `Right ⌥` remap reference.
- `AGENTS.md` — test count updated to 98 tests in 13 suites.
- `CHANGELOG.md` — added `[Unreleased]` for the `INJ-05`, `CORE-02`, and `BUILD-05` fixes and marked the 1.3.0 Automation entry as superseded.

**Guardrail:** keep the docs in the same commit as behavior changes. The remaining `BUILD-04` item is now a product decision (CPU vs. Metal), not a documentation contradiction.

### REPO-01 · Hygiene and automation

**Status:** Open (CI portion fixed).

- ~~No CI (build + `swift test` + release compile).~~ Added in `78dbd4a` (`.github/workflows/ci.yml`); it runs debug build, `swift test`, and release build on macOS 15.
- No `swift-format`/`swiftlint` config; formatting is inconsistent (trailing spaces on blank lines, mixed import order, `setupMenuBar() {        statusItem` on one line).
- `.DS_Store` present at the root (ignored, but noise).
- The `render_*.swift` / `inspect_*.swift` design scripts are still tracked and reference machine-specific absolute paths; move them to `scripts/design/` with parameterised paths or remove them.
- ~4 MB of simulator binaries (`echo-spike*`, `render_*`, `inspect_*`) sit in the working tree (ignored); consider deleting them and relying on git history.
- The root harnesses and the `--test` branch still exist and still print "PASSED (100% Operational)" without assertions (`EchoApp.swift:30-62`). Keep them as a smoke test if useful, but label them clearly and make failures non-zero.
- Consider a `Makefile`/`justfile` with `build`, `test`, `bundle`, `release` targets so the README stops carrying copy-paste commands.
- The release zips (`Echo-v1.2.0`, `Echo-v1.3.0`) are present in the tree (ignored) and consume ~4.5 MB; remove before archiving.

### REPO-02 · Pre-existing failing harness

**Status:** ✅ Fixed in `78dbd4a`. `test_injection.swift` expected `prepareText` to return lowercase, but `prepareText` runs sentence capitalization (added in v1.2.0); the harness aborted at test 1, so tests 2–4 never ran. It also wrote into the production database and read the session before the main-queue append ran — both fixed by injecting a temporary database and draining the main queue.

**Fix:** update the expectation to the capitalized string, then move the file into `Tests/EchoTests` per QLT-01. The assertions now live in `TextInjectorTests`, and the root harness remains as a manual end-to-end check that uses a temporary database.

---

## Suggested sequencing

Done: QLT-01/REPO-01 (CI), AUD-01, ENG-01/ENG-02, AUD-02–AUD-06, CFG-01, BUILD-01, BUILD-05, DATA-01 (first pass), UX-02, UX-04, SEC-01, SEC-02, LEX-01, INJ-01/INJ-02/INJ-03/INJ-04/INJ-05, UX-01, CORE-02, CORE-03, DOC-01.

Remaining, in order:

1. **DATA-02 + DATA-03** — move the live persistence path off `MainActor`, stop persisting empty sessions every launch, and add retention/history.
2. **BUILD-04** — benchmark CPU vs. Metal/MLX on this machine and make the default deliberate. Docs already say CPU, so this is now a performance task.
3. **CORE-01** — enable strict concurrency in a branch; fix the remaining 22 `@unchecked Sendable` sites it exposes (start with `HotkeyManager`).
4. **UX-03, UX-05, UX-06** — intrinsic HUD width, export scope/picker, and word-boundary notes extraction.
5. **BUILD-02 + REPO-01** — inner-to-outer signing/notarization, formatter config, script/binaries cleanup, Makefile.

---

## Verification performed for this review

Re-audited `dd92480`…`bce471d` (1.3.0/1.3.1) against the source on 2026-11-19.

- `swift build` — clean.
- `swift build -c release` — clean.
- `swift test` — **98 tests in 13 suites passing** (audio store, converter, VAD, AudioHub, transcription queue, SQLite, word memory, formatting/injection, export, coordination, notes extraction, hotkeys, settings). New coverage includes the focused-app shortcut path and the non-destructive clipboard contract (AX untouched, restore on success, transcript retained on total failure).
- Static checks: `git diff --stat 78dbd4a..HEAD` (37 source/test files, +4,260/−921), grep for remaining `objectWillChange` (1), `@unchecked Sendable` (22), unused async DB wrappers (production: 0 call sites), and stale plist keys.
- Duplicate-shortcut dispatch (`INJ-05`) confirmed with a throwaway AppKit harness: one local `.keyDown` monitor plus one `⇧⌘` menu key equivalent produced `monitor=1 menu=1` for a synthesized event.
- Not exercised (environment-limited): live microphone/system-audio capture and TCC prompts, a real `fermion` binary, and multi-monitor HUD placement. These need a manual pass with the app bundle.

_This document reflects `bce471d` (v1.3.1). Mark items ✅ when fully fixed, 🟡 when partially fixed, and keep the IDs stable so commit messages can reference them._
