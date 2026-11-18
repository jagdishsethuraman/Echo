# Echo — Code Review: Remaining Improvements

**Reviewed:** 2026-11-17 · **Baseline commit:** `e250a3a` · **P0 fixed through:** `78dbd4a` · **Scope:** `Sources/Echo` (27 files, ~4k LOC), build scripts, tests, docs

This document captures the findings that were **not** addressed in `e250a3a`. All four P0 items have since been fixed; their rationale is kept below so the backlog stays self-contained. Each item has an ID so it can be referenced from commits and issues.

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
| AUD-05 | P1 | Correctness | `stopSession()` returns before flushed audio is transcribed | ✅ Fixed |
| AUD-06 | P1 | Quality | System-audio meter assumes Int16; capture failures stop silently | ✅ Fixed |
| ENG-02 | P1 | Performance | Unbounded concurrent `fermion` processes per segment | ✅ Fixed |
| DATA-01 | P1 | Product model | Quick dictations are appended to the active meeting; startup restores yesterday's session | ✅ Fixed |
| DATA-02 | P1 | Storage | SQLite runs on the main thread; no migrations, busy timeout, foreign keys, or history UI | ✅ Fixed |
| CORE-01 | P1 | Concurrency | Pervasive `@unchecked Sendable`; no strict-concurrency checking | ✅ Fixed |
| CORE-02 | P1 | SwiftUI | `objectWillChange.send()` before mutating `@Published` causes double invalidation | ✅ Fixed |
| CORE-03 | P1 | Safety | Force-cast `focusedElement as! AXUIElement` in the injection path | ✅ Fixed |
| LEX-01 | P1 | Text quality | Sanitizer can cascade, breaks on `$`/`\` replacements, ASCII-only boundaries, no regex cache | ✅ Fixed |
| INJ-01 | P2 | UX | Global `⌃ Control` hotkey fires on every Control shortcut; no cancel or speech gate | ✅ Fixed |
| INJ-02 | P2 | UX | Documented global shortcuts are menu key equivalents and only work when Echo is focused | Open |
| INJ-03 | P2 | UX | Typing is preferred over paste; user clipboard is wiped despite "non-destructive" docs | Open |
| INJ-04 | P2 | UX | No feedback when microphone or system-audio capture fails; `statusMessage` is never rendered | Open |
| UX-01 | P2 | UI | "Live AI Executive Notes" is hardcoded placeholder content | ✅ Fixed |
| UX-02 | P2 | Performance | Entire Studio view invalidates at audio rate (~43 Hz) | Open |
| UX-03 | P2 | UI | HUD width is guessed from character count; `NSScreen.main` is wrong on multi-monitor setups | ✅ Fixed |
| UX-04 | P2 | Lifecycle | No graceful shutdown: audio not stopped, session `endTime` not written, temp files left behind | Open |
| SEC-01 | P2 | Privacy | Sensitive WAVs are written to world-readable `/tmp` and may survive crashes | Open |
| UX-05 | P2 | UX | "Export All Notes" exports only the active session | Open |
| SEC-02 | P3 | Permissions | AppleScript fallback triggers Automation TCC but the bundle lacks `NSAppleEventsUsageDescription` | ✅ Fixed |
| BUILD-01 | P3 | Reproducibility | `Info.plist` and bundle assembly are not in version control | ✅ Fixed |
| BUILD-02 | P3 | Distribution | `codesign --deep` guidance; no hardened runtime or notarization | Open |
| BUILD-03 | P3 | Cleanup | Dead code: `PhononClient`, `BenchmarkResult`, unused enum case, unused field | Open |
| BUILD-04 | P3 | Performance | `FERMION_DEVICE=cpu` contradicts documented Metal/MLX acceleration | Open |
| DOC-01 | P3 | Docs | README/ARCHITECTURE/ROADMAP/CHANGELOG disagree with the code | Open |
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
| `Tests/` was empty and `--test` always reported success (QLT-01, REPO-02) | 63 Swift Testing cases, CI workflow, hermetic harness fixes | `78dbd4a` |

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

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:153-171`, `Sources/Echo/Audio/VoiceActivityDetector.swift:90-94`

`flush()` dispatches the segment callback asynchronously, then `stopSession()` immediately writes `endTime` and returns. The final utterance is appended after the session "ended" and can miss the export. Two VADs also produce segments whose transcription order is not guaranteed.

**Fix:** track in-flight transcription tasks, await them in `stopSession()` (with a timeout), and serialize transcription through an ordered queue.

### AUD-06 · System-audio meter assumes Int16; capture failures are silent

**Status:** ✅ Fixed. ScreenCaptureKit sample buffers are decoded through `AudioBufferConverter.pcmBuffer` and `calculateRMS`; `didStopWithError` invokes `onCaptureFailed` and fans out via `AudioHub.addErrorObserver`.

**Where:** `Sources/Echo/Audio/SystemAudioCapture.swift:79-98`, `:100-104`

The VU meter reinterprets ScreenCaptureKit samples as `Int16` without checking the stream format; those buffers are commonly `Float32`, so the meter can read nonsense. `didStopWithError` clears the flag but notifies nobody, so a dropped stream looks like a healthy recording.

**Fix:** compute the meter from the already-converted 16 kHz buffer (reuse `AudioBufferConverter`), and expose a callback/error state that the Studio can display and optionally auto-restart.

### ENG-02 · Unbounded concurrent transcription processes

**Status:** ✅ Fixed. Handled via bounded `TranscriptionService` with serialization and backpressure.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:89-103`, `:173-211`

Each VAD completion spawns `Task { await processSpeechSegment(...) }`, which launches a new `fermion` process. Two VADs plus push-to-talk can run several heavy inference processes at once, and a long meeting can queue faster than it drains.

**Fix:** a bounded `TranscriptionService` actor (serial queue or max 1–2 in flight) with back-pressure; ideally one persistent server process (wire up the existing `PhononClient` or keep `fermion` running on stdin/stdout) so model load isn't paid per utterance.

### DATA-01 · Dictation and meetings share one timeline

**Status:** ✅ Fixed. Closed sessions (`endTime != nil`) are not revived as active recording streams on startup; standalone quick dictations are saved to SQLite dictations log and do not pollute active meeting timelines.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:33-42`, `:104-132`; `Sources/Echo/AppCoordinator.swift:262`

Startup restores the most recent session as `activeSession`, so today's quick dictations are appended to yesterday's meeting. "Start Meeting" replaces `activeSession`, hiding earlier dictations from the UI even though they are in SQLite. There is no session history browser.

**Fix:** separate "dictation log" from "meeting session" (different streams/views), start sessions explicitly, and add a sidebar of past sessions with search (roadmap v1.1/v2.0).

### DATA-02 · SQLite lifecycle and schema hardening

**Status:** ✅ Fixed. Configured `PRAGMA busy_timeout = 3000` + `sqlite3_busy_timeout`, `PRAGMA foreign_keys = ON`, `FOREIGN KEY ... ON DELETE CASCADE` on utterances, `PRAGMA user_version` migrations, `deleteSession()` with cascading cleanup, `checkpointWAL()`, and dedicated `dbQueue` async wrappers.

**Where:** `Sources/Echo/Storage/DatabaseManager.swift` (all public methods)

- Every read/write runs synchronously on the main actor when called from SwiftUI/coordinators.
- No `user_version` / migration path; schema changes will require manual handling.
- No `busy_timeout`, no `foreign_keys`, no `ON DELETE CASCADE` from `utterances` to `sessions`.
- `idx_dictionary_pattern` duplicates the index created by `UNIQUE(raw_pattern)`.
- No session deletion / retention / compaction; WAL can grow indefinitely.
- Failures (`sqlite3_prepare_v2`, `sqlite3_step`) are still ignored outside the dictionary upsert.

**Fix:** move storage behind an actor or serial queue, add a versioned migration runner, `PRAGMA busy_timeout = 3000`, `PRAGMA foreign_keys = ON`, a `sessions → utterances` cascade, and centralized SQLite error handling/logging.

### CORE-01 · `@unchecked Sendable` everywhere

**Status:** ✅ Fixed. Synchronized cross-thread callback closures with locks in `SystemAudioCapture`, `AudioEngineManager`, and `MeetingCoordinator`; marked UI state `WordMemoryState` with `@MainActor`.

**Where:** `DatabaseManager`, `WordMemoryEngine`, `WordMemoryState`, `MeetingCoordinator`, `AudioEngineManager`, `DualChannelCoordinator`, `SystemAudioCapture`, `HotkeyManager`, `TextInjector`, `PhononProcessRunner`, `PhononClient`

The annotation is used to silence the compiler rather than to document a real guarantee. AppKit/SwiftUI types (panels, windows) are callable from any thread, and mutable state crosses audio/main/SCK queues — for example, the audio callback closures are invoked on the audio thread while callers reassign them from the main actor.

**Fix:** adopt Swift 6 language mode / strict concurrency. Mark UI types `@MainActor`, make storage and the transcription pipeline actors, and use `@Sendable` only where the closure truly is. Expect this to surface several real races.

### CORE-02 · Double SwiftUI invalidation

**Status:** ✅ Fixed. Removed redundant manual `objectWillChange.send()` calls; `@Published` property wrapper handles notification.

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:134`, `:156`, `:178`

Calling `objectWillChange.send()` before mutating an `@Published` property sends two change notifications and can render a half-updated state.

**Fix:** mutate the `@Published` value only; delete the manual sends.

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

**Where:** `Sources/Echo/UI/MenuBarManager.swift:112-151`

`⇧⌘E`, `⇧⌘D`, `⇧⌘C`, `⇧⌘R` are `NSMenuItem.keyEquivalent`s. In an `.accessory` app they only fire while Echo or its menu is focused. README lists them as global shortcuts.

**Fix:** register them with Carbon `RegisterEventHotKey` (or a global `NSEvent` keyDown monitor) and/or update the README to say "menu shortcuts".

### INJ-03 · Injection order and clipboard behaviour

**Where:** `Sources/Echo/Injection/TextInjector.swift:312-344`, `:198-247`

- Direct Unicode typing (up to 300 chars, ~1.5 ms/char) is tried **before** `Cmd+V`. It is slower, can interleave with the user's own typing, and has no rollback if it partially fails.
- `clearContents()` destroys the user's clipboard, contradicting README/CHANGELOG claims of non-destructive retention.
- `prepareText` capitalizes before checking `useDirectTyping`; the "direct typing" path still types a 300-char string even when paste would be instant.

**Fix:** cascade AX insert → paste → typing; snapshot and restore the previous pasteboard after a successful paste (or explicitly document that Echo owns the clipboard); add a preference for injection order.

### INJ-04 · Silent audio failures; unused status surface

**Where:** `Sources/Echo/AppCoordinator.swift:151`, `:19`, `Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift:109`

`try? micEngine.startCapture()` swallows permission and device errors, so the HUD says "Listening" while capturing nothing. `statusMessage` is published but never rendered. The accessibility banner recomputes `AXIsProcessTrusted()` in `body`, so it doesn't refresh when permission changes.

**Fix:** request microphone access explicitly (`AVCaptureDevice.requestAccess(for: .audio)`), surface a state/banner for denied permission, remove or render `statusMessage`, and observe AX trust changes (notification/`Timer`/on-activate refresh).

### UX-01 · Hardcoded "AI" notes

**Status:** ✅ Fixed. Created `MeetingNotesExtractor` with linguistic sentence analysis to extract real decisions and action items dynamically from transcript utterances in real time. Replaced hardcoded strings with live dynamic cards, empty state guidance, and interactive user item management.

**Where:** `Sources/Echo/Engine/MeetingNotesExtractor.swift`, `Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift`

"Key Decisions" and "Action Items" are literal strings, including "Single binary unified app (saves 1.2 GB RAM)". The panel is labelled "LIVE AI EXECUTIVE NOTES".

**Fix:** generate them from the transcript (v1.1 local LLM), or label the cards as static placeholders until then.

### UX-02 · Studio re-renders at audio rate

**Where:** `Sources/Echo/Engine/MeetingCoordinator.swift:82-90`, `Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift`

`micLevel` / `systemLevel` are `@Published` and updated ~43×/s, invalidating the whole studio (including the full transcript list) each frame.

**Fix:** throttle levels to ~10 Hz, isolate meters in their own `ObservableObject`/`Canvas`, and avoid observing them from the timeline subtree.

### UX-03 · HUD sizing and screen selection

**Status:** ✅ Fixed. Anchored Floating Pill dynamically to display containing the mouse pointer (`NSMouseInRect(mouseLoc, screen.frame)`), falling back to `NSScreen.main`. Expanded base width to house discard button and status hints comfortably.

**Where:** `Sources/Echo/UI/FloatingPillPanel.swift`

Width is estimated as `characterCount × 7.5` (`:102`, `:108`, `:111`), which breaks for wide glyphs, emoji, and CJK. `NSScreen.main` (`:117`) is unreliable for a non-key panel on multi-monitor setups.

**Fix:** measure with `NSAttributedString.size()` or let `NSHostingView.fittingSize` drive the window; anchor to the screen containing the mouse or the frontmost window.

### UX-04 · No graceful shutdown / crash cleanup

**Where:** `Sources/Echo/main.swift`, `Sources/Echo/AppCoordinator.swift`

No `applicationWillTerminate`: recording is not stopped, the active session's `endTime` is not written, pending transcriptions are not awaited, and temp WAVs are not swept. A crash leaves files behind.

**Fix:** implement `applicationShouldTerminate` / `applicationWillTerminate` async shutdown, add a launch-time sweep of stale `echo_*.wav` files, and stop audio before exiting.

### SEC-01 · Sensitive audio in world-readable temp

**Where:** `Sources/Echo/AppCoordinator.swift:188-193`, `:243-248`, `Sources/Echo/Engine/MeetingCoordinator.swift:176`

Every partial and segment is written to `FileManager.default.temporaryDirectory` with default permissions. On macOS `/var/folders/...` is per-user, but the files are still readable by any process of the user and survive crashes.

**Fix:** use an app-support `Recordings/tmp` directory created with `0700`, write files with `0600`, delete with `defer`, and sweep on launch. Longer term, pipe audio to a persistent decoder to avoid disk entirely.

### UX-05 · Export scope is misleading

**Where:** `Sources/Echo/AppCoordinator.swift:333-346`, `Sources/Echo/UI/MenuBarManager.swift:156-162`

"Export All Notes to Obsidian (.md)" exports only `activeSession` (and an empty session if none), to a fixed folder. Failure is ignored.

**Fix:** rename to "Export Current Session", add a session picker/history, report success/failure, and remember the last export location.

---

## P3 — Build, security, docs, hygiene

### SEC-02 · AppleScript fallback vs. Automation permission

**Where:** `Sources/Echo/Injection/TextInjector.swift:300-308`; `Echo.app/Contents/Info.plist`

`NSAppleScript` ("System Events keystroke v") requires Automation consent. The bundle has no `NSAppleEventsUsageDescription`, so the fallback can produce the exact "Echo would like to control System Events" prompt loop the changelog says was fixed.

**Fix:** remove the AppleScript fallback (AX + `CGEvent` is sufficient), or gate it behind an explicit opt-in and add `NSAppleEventsUsageDescription` to the plist. Prefer not to depend on Automation for core dictation.

### BUILD-01 · Bundle assembly is not reproducible

**Where:** `Package.swift`, `Echo.app/Contents/Info.plist` (ignored), README "Compiling from Source"

`Info.plist` exists only inside the ignored `.app`; version, usage strings, `LSUIElement`, and icon mapping are not in the repo. A fresh clone cannot rebuild the shipping bundle with the README commands, and version numbers live in several places.

**Fix:** check in `Support/Info.plist` (with `$(MARKETING_VERSION)`-style values or a script that stamps it), add `scripts/build_app.sh` that compiles, assembles, signs, and zips, and keep one source of truth for the version.

### BUILD-02 · Signing and distribution

**Where:** README "Packaging & Code Signing"

`codesign --deep` is deprecated for signing and can hide missing inner signatures. Ad-hoc signing with an identifier-only designated requirement is fine for local development but not distributable.

**Fix:** sign inner-to-outer (`--force --options runtime --timestamp --sign "Developer ID Application: …"`), notarize with `notarytool`, and staple. Keep the documented ad-hoc recipe only for local dev, clearly labelled.

### BUILD-03 · Dead code

- `Sources/Echo/Engine/PhononClient.swift` — a complete HTTP transcription client that nothing calls.
- `Sources/Echo/Engine/STTTypes.swift:11` — `BenchmarkResult` unused; `PhononClientError.invalidURL` unused.
- `Sources/Echo/Injection/HotkeyManager.swift:13` — `lastKeyUpTime` written but never read.
- `Sources/Echo/Engine/PhononProcessRunner.swift:38` — process failures are reported as `PhononClientError.serverError`, which is misleading.

**Decision:** either wire `PhononClient` to a persistent local server (recommended — fixes ENG-01/ENG-02 and model reload), or delete it. Rename the process error case.

### BUILD-04 · CPU vs. documented GPU acceleration

**Where:** `Sources/Echo/Engine/PhononProcessRunner.swift:19`

`FERMION_DEVICE=cpu` contradicts README/ARCHITECTURE claims of Metal/MLX acceleration. Either the claims or the setting are wrong.

**Fix:** benchmark `metal`/`mlx` vs `cpu`, default to the fastest reliable path, and expose it as a setting.

### DOC-01 · Documentation drift

| Document | Says | Code |
| :--- | :--- | :--- |
| `README.md:42,85,100` | Hold `Right ⌥` | `⌃ Control` |
| `README.md:85-90` | "Global" `⇧⌘…` shortcuts | Menu-only key equivalents |
| `README.md:62` | "3-tier injection" | 4 paths (AX, typing, Cmd+V, AppleScript) |
| `ARCHITECTURE.md:175` | HUD level `.floating` | `.statusBar` (`FloatingPillPanel.swift:19`) |
| `ROADMAP.md:10,38` | v1.1 is "CURRENT", v1.2 "PLANNED" | `CHANGELOG.md` is at 1.2.0 |
| `CHANGELOG.md:14` | Double-tap window 380 ms | 350 ms hold / 260 ms double-tap |

**Fix:** treat docs as code — update them in the same commit, and add a short "what changed" checklist to the PR template.

### REPO-01 · Hygiene and automation

- ~~No CI (build + `swift test` + release compile).~~ Added in `78dbd4a` (`.github/workflows/ci.yml`).
- No `swift-format`/`swiftlint` config; formatting is inconsistent (trailing spaces on blank lines, mixed import order).
- `.DS_Store` present at the root (ignored, but noise).
- Icon/mockup scripts reference `~/.gemini/antigravity/...` absolute paths and are tracked; move them to `scripts/design/` with parameterised paths or remove.
- ~4 MB of simulator binaries (`echo-spike*`, `render_*`, `inspect_*`) sit in the working tree (ignored); consider deleting them and relying on git history.
- Consider a `Makefile`/`justfile` with `build`, `test`, `bundle`, `release` targets so the README stops carrying copy-paste commands.

### REPO-02 · Pre-existing failing harness

**Status:** ✅ Fixed in `78dbd4a`. `test_injection.swift` expected `prepareText` to return lowercase, but `prepareText` runs sentence capitalization (added in v1.2.0); the harness aborted at test 1, so tests 2–4 never ran. It also wrote into the production database and read the session before the main-queue append ran — both fixed by injecting a temporary database and draining the main queue.

**Fix:** update the expectation to the capitalized string, then move the file into `Tests/EchoTests` per QLT-01. The assertions now live in `TextInjectorTests`, and the root harness remains as a manual end-to-end check that uses a temporary database.

---

## Suggested sequencing

1. ~~**QLT-01 + REPO-01** — get `swift test` and CI green first.~~ Done; every later fix should now land with a test.
2. **AUD-01 + ENG-01 + ENG-02** — replace the partial-decode loop with a bounded window and put transcription behind one cancellable, time-limited service. This is the biggest perceived-quality win.
3. **CFG-01 + BUILD-01** — make the app runnable on a machine that is not this one.
4. **AUD-02/AUD-03/AUD-04 via one `AudioHub`** — removes duplicate capture and fixes clipped onsets.
5. **DATA-01/DATA-02** — split dictation from meetings, add migrations and a session history view.
6. **CORE-01** — enable strict concurrency and fix what it finds (expect real races).
7. **INJ-01…INJ-03 + UX-01…UX-03** — product polish, once the plumbing is trustworthy.
8. **SEC-01/SEC-02, BUILD-02, DOC-01, REPO-01** — release readiness and cleanup.

---

## Verification performed for this review

- `swift build` and `swift build -c release` — clean.
- `swift test` — 63 tests in 9 suites passing (audio store, converter, VAD, SQLite, word memory, formatting/injection, export, coordination, settings).
- Legacy harnesses: `test_database.swift` 5/5, `test_injection.swift` 4/4.
- Process-runner harness (throwaway): 1.17 MB of stdout drained without deadlock, 1 s timeout fired at 1.07 s, cancellation completed in 0.27 s.

_This document reflects `78dbd4a` (P0 all fixed). Strike through or delete items as they land, and keep the IDs stable so commit messages can reference them._
