# Echo repository audit

Reviewed 19 November 2026 at [commit 379f023c64c8](https://github.com/jagdishsethuraman/Echo/tree/379f023c64c86cc14959b5c2030d8921539cb8e9).

## What to fix first

Start with meeting finalization, session ownership and engine-failure reporting. A healthy-looking recording can produce no transcript, and a slow transcription can land in a later meeting. These defects affect the reliability of the saved record. Edited notes and database migrations also deserve attention before users entrust Echo with irreplaceable meetings.

## Scope and verification

Reviewed the SwiftPM macOS app, including microphone and system audio capture, dictation and injection, the local engine, SQLite, vocabulary, Meeting Studio, export, tests, assembly, CI and onboarding. Compared the implementation with the repository’s earlier CODE_REVIEW.md. Its five-second drain and concurrency limiter are present. Their behavior under backlog is described below.

A clean checkout compiled with Apple Swift 6.4.2 on arm64 macOS. **All 113 Swift Testing tests in 14 suites passed.** The release configuration also built successfully. Findings below come from tracing source paths. The checks proposed for each finding are regression tests to add. Live microphone and system capture, real fermion inference, cross-app paste, VoiceOver, signing identity continuity and notarized distribution were outside the executed checks. No source changes were made.

## Findings

High priority indicates potential loss, misdelivery or mixing of user data, or sustained resource exhaustion. Medium priority covers operational and correctness issues with narrower triggers. Lower priority covers onboarding, maintainability and performance improvements.

### 1. Late speech can enter the next meeting

**High priority.** Stop waits five seconds, then closes the session even when inference is still running. The completion looks up the current session when it returns. A slow result from meeting A can therefore appear in meeting B, and A’s first export can omit it.

Bind each segment to a session ID at capture. Track outstanding work per session and expose a finalizing state. Test a delayed completion after B starts and check both exports.

[MeetingCoordinator.swift L158](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L158) · [MeetingCoordinator.swift L270](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L270)

### 2. Quitting bypasses the final speech flush

**High priority.** The termination delegate invokes synchronous shutdown. Shutdown schedules capture stop, sets the end time, checkpoints storage and sweeps WAVs without awaiting the VAD flush or transcription queue. The last spoken sentence can disappear.

Use AppKit’s deferred termination flow and a single awaited meeting finalizer. Quit mid-sentence with a delayed engine and verify the final words after relaunch.

[EchoApp.swift L5](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/EchoApp.swift#L5) · [AppCoordinator.swift L550](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L550)

### 3. A meeting can record with no working transcription engine

**High priority.** The runner throws when fermion is missing. Meeting submission converts errors to nil, and the completion drops nil. Capture can appear healthy while every utterance disappears. The same path hides timeouts and write failures.

Check engine readiness before recording, propagate typed failures to Studio, and show how many segments failed. Test a missing executable and a failure halfway through a session.

[PhononProcessRunner.swift L26](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/PhononProcessRunner.swift#L26) · [TranscriptionService.swift L50](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/TranscriptionService.swift#L50) · [MeetingCoordinator.swift L159](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L159)

### 4. Overlapping dictations share results and destinations

**High priority.** Finalization clears isDictating before awaiting inference. A second recording can start while the first still owns callbacks. The old partial checks only isDictating, the final reads shared fallback text and current meeting state, and injection resolves the field focused at completion. A user switching apps can send private text to the wrong field.

Give each recording its own state, originating meeting ID and destination. Validate focus before injection and offer manual paste on a mismatch. Test two rapid recordings with inverted completion order and a focus change.

[AppCoordinator.swift L274](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L274) · [AppCoordinator.swift L321](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L321) · [TextInjector.swift L335](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Injection/TextInjector.swift#L335)

### 5. Migration failure can advance the schema version

**High priority.** If v1 creates the sessions table but a later statement fails, execution continues to v2 using the original version. Its index can succeed and mark the partial database as version 2. Future launches then skip the missing schema.

Run each migration and version bump in a transaction. Stop on the first error and surface a recovery action. Use a deliberately incompatible legacy table in a temporary database and verify rollback.

[DatabaseManager.swift L147](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/DatabaseManager.swift#L147) · [DatabaseManager.swift L173](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/DatabaseManager.swift#L173)

### 6. Edited action items can leak across meetings or disappear from exports

**High priority.** Studio stores manual items and completion flags in view state. Its merge only appends, and the host reuses the same view across sessions. Studio Export rebuilds items from speech and marks every one incomplete. A checked task or manual addition can differ between Copy and Export.

Persist items by session ID with stable item IDs. Feed the same saved model to Studio, Copy and Export. Add and complete an item in A, open B, then relaunch and export A.

[MeetingStudioView.swift L63](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift#L63) · [MeetingStudioView.swift L102](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift#L102) · [MeetingStudioWindow.swift L60](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MeetingStudio/MeetingStudioWindow.swift#L60)

### 7. The inference backlog retains unlimited meeting audio

**High priority.** The semaphore caps running processes, but submit creates a task retaining PCM for every segment before it acquires a slot. A slow engine can accumulate audio throughout a long call. Dictation partials also bypass this limiter.

Set an explicit pending-byte or audio-duration budget and surface overload. Coordinate meeting and dictation scheduling. Test sustained input faster than inference and measure peak queued bytes and finalization latency.

[TranscriptionService.swift L50](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/TranscriptionService.swift#L50) · [AppCoordinator.swift L312](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L312)

### 8. Repeated meeting toggles can create phantom sessions

**Medium priority.** The active flag changes after the awaited start or stop. Two starts can each allocate and save a session while the capture layer treats the second start as already running. A failed start clears memory but leaves the inserted open row until pruning.

Serialize starting, recording and stopping transitions. Persist after successful start or roll back the row. Test a double toggle during startup and a microphone failure.

[AppCoordinator.swift L444](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L444) · [MeetingCoordinator.swift L232](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L232) · [DualChannelCoordinator.swift L80](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/DualChannelCoordinator.swift#L80)

### 9. A truncated preview can be delivered as a complete dictation

**Medium priority.** Finalization substitutes the recent 12-second partial when the full decode returns empty, strips its truncation marker, and saves and injects it with the full duration.

Track preview coverage. Offer an explicitly labeled partial recovery when the full result is empty. Verify with a 30-second dictation whose final decode returns empty.

[AppCoordinator.swift L41](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L41) · [AppCoordinator.swift L349](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L349)

### 10. Timeline timestamps measure inference completion

**Medium priority.** Meeting segments get Date() after queued recognition. Backlogs move utterances later than they were spoken. Independent submission tasks can also reach inference in a different order from capture.

Record timestamp and sequence at the audio boundary. Store and display using capture order. Delay one speaker’s inference and compare exported times against input times.

[MeetingCoordinator.swift L144](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L144) · [MeetingCoordinator.swift L166](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L166)

### 11. Session and utterance writes can partially succeed

**Medium priority.** The background wrapper performs two independent saves and returns Void. The UI appends the segment before persistence, so a failed utterance write can leave an apparently saved transcript that vanishes on relaunch. Session deletion also reports success without a result.

Use one transaction and return a typed outcome. Show pending or failed saves, and confirm deletion only after success. Simulate a failed second write and verify the UI and database agree.

[DatabaseManager.swift L384](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/DatabaseManager.swift#L384) · [MeetingCoordinator.swift L174](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L174) · [AppCoordinator.swift L472](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L472)

### 12. Storage can silently switch to a temporary database

**Medium priority.** When the primary database cannot open, Echo tries a hidden home-directory database and then a temporary one. Only console output identifies the fallback. History can appear empty or disappear after the original path becomes available.

Expose the active storage location and degraded state. Require a deliberate recovery choice before using volatile storage. Test reopening after the primary directory becomes writable.

[DatabaseManager.swift L90](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/DatabaseManager.swift#L90)

### 13. Standalone dictations lack a matching deletion control

**Medium priority.** Standalone speech is saved with a null session ID. The history deletion flow takes a meeting UUID, so deleting a meeting or pruning empty sessions cannot remove those rows.

Add standalone history deletion and a configurable retention choice. Verify that purging dictations removes standalone rows while preserving meetings.

[AppCoordinator.swift L367](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L367) · [DatabaseManager.swift L572](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/DatabaseManager.swift#L572) · [MenuBarManager.swift L289](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MenuBarManager.swift#L289)

### 14. Clipboard restoration can overwrite a newer copy

**Medium priority.** After synthetic paste, Echo waits 60 ms and unconditionally restores its snapshot. A copy made by the user or another app during that window can be lost. Posting the keystroke also supplies no acknowledgement that the target read it.

Restore only if pasteboard changeCount still matches Echo’s write. Describe posted events accurately and keep a manual recovery path. Exercise a concurrent copy and a slow paste target.

[TextInjector.swift L386](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Injection/TextInjector.swift#L386) · [TextInjector.swift L445](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Injection/TextInjector.swift#L445)

### 15. Direct typing can split an emoji and report partial delivery as success

**Medium priority.** The event poster emits individual UTF-16 code units, skips a unit if event creation fails, and returns true after the loop. Supplementary characters span two units.

Emit complete character sequences and distinguish partial delivery to prevent duplicate retries. Check emoji, combining marks and a simulated event allocation failure.

[TextInjector.swift L51](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Injection/TextInjector.swift#L51)

### 16. Two capture consumers can disagree on whether startup succeeded

**Medium priority.** AudioHub increments its retain count before the hardware start completes. A concurrent second consumer returns successfully. If the first start then fails, the count can remain positive with no running engine.

Serialize the underlying start and stop operations and share the pending start result with all retainers. Test two concurrent retains and one failed hardware start.

[AudioHub.swift L131](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/AudioHub.swift#L131) · [AudioHub.swift L229](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/AudioHub.swift#L229)

### 17. System audio can pass twice through the same stateful converter

**Medium priority.** The system capture callback sends the raw buffer to the meeting observer, then converts it for the meter. The observer also converts it. For noncanonical formats the format-keyed global converter advances twice for one chunk, potentially disturbing continuity. Canonical input still incurs duplicate buffer copies.

Convert once per stream, share the converted buffer and RMS, and reset the converter on stream changes. Compare a sequence of noncanonical chunks to a single-pass reference.

[SystemAudioCapture.swift L91](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/SystemAudioCapture.swift#L91) · [MeetingCoordinator.swift L114](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L114) · [AudioBufferConverter.swift L83](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/AudioBufferConverter.swift#L83)

### 18. VAD silence timing depends on callback size

**Medium priority.** The detector counts chunks against a threshold calculated from only the latest chunk length. Mixed buffer sizes can cut speech early or late. Pre-roll and trailing silence also count toward the minimum speech duration, letting a brief noise burst pass.

Accumulate silent and voiced sample counts separately. Test identical audio split into uneven chunks and an isolated impulse followed by silence.

[VoiceActivityDetector.swift L55](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/VoiceActivityDetector.swift#L55) · [VoiceActivityDetector.swift L112](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/VoiceActivityDetector.swift#L112)

### 19. A second process can sweep audio belonging to a live recording

**Medium priority.** Startup and shutdown remove every WAV in a shared scratch directory. A second executable instance or assembly self-test can remove another process’s in-flight input. The self-test also constructs the production coordinator, which prunes storage.

Isolate scratch files by process and session, establish liveness before orphan cleanup, and inject disposable storage for self-tests. Run two isolated instances with overlapping file lifetimes.

[AudioTempDirectory.swift L43](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Audio/AudioTempDirectory.swift#L43) · [EchoApp.swift L13](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/EchoApp.swift#L13) · [MeetingCoordinator.swift L67](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Engine/MeetingCoordinator.swift#L67)

### 20. Export has different effects across entry points

**Medium priority.** Studio’s Export Notes only writes to the clipboard. The coordinator also writes a file, using a timestamp with second precision. Two sessions started in the same second can overwrite the same file. History export synchronously reads and formats the full session on the main actor.

Separate Copy and Save actions, share one document generator, move file and database work off the main actor, and include a stable session identifier in filenames. Compare Studio and history exports of two same-second sessions.

[MeetingStudioWindow.swift L70](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MeetingStudio/MeetingStudioWindow.swift#L70) · [AppCoordinator.swift L500](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L500)

### 21. Assembly reports success with a missing engine

**Medium priority.** The assembly script trusts --test. That branch prints the resolved runner path or ‘not found’, unconditionally announces that hotkeys are ready, and exits successfully. CI builds the release executable but never validates the assembled bundle.

Make the smoke test assert bundle invariants and return a failing exit code for unmet prerequisites of the tested configuration. Add isolated bundle assembly to CI and keep a separate hardware acceptance run.

[EchoApp.swift L30](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/EchoApp.swift#L30) · [assemble_app.sh L19](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/assemble_app.sh#L19) · [ci.yml L21](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/.github/workflows/ci.yml#L21)

### 22. First-run instructions depend on the original developer’s setup

**Lower priority.** Quick Start opens an absolute path, omits engine provisioning, and promises persistent Accessibility permission. The supplied assembly script ad-hoc signs without the explicit requirement shown later in the README. The hands-free description also conflicts with the ten-minute cap.

Document a fresh-clone SwiftPM build, supported engine/model setup and readiness check, and distinguish local builds from signed releases. Verify on a clean account. Publish measured latency with device, hardware and audio length.

[README.md L34](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/README.md#L34) · [assemble_app.sh L7](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/assemble_app.sh#L7) · [EchoSettings.swift L45](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/EchoSettings.swift#L45) · [AppCoordinator.swift L46](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/AppCoordinator.swift#L46)

### 23. Empty vocabulary is indistinguishable from first launch

**Lower priority.** Deleting all entries leaves the table empty. On the next initialization the engine interprets that as a fresh install and restores all bundled terms.

Record completion of initial seeding separately from entry count. Test deleting the last term and reopening the database.

[WordMemoryEngine.swift L16](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/WordMemoryEngine.swift#L16) · [WordMemoryEngine.swift L51](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/Storage/WordMemoryEngine.swift#L51)

### 24. Studio rescans meeting history as segments arrive

**Lower priority.** syncActionItems re-extracts from all segments and linearly searches existing tasks for each extracted item. Decisions are also computed from the whole transcript. This work grows during the meetings where responsiveness matters most.

Cache extraction by segment ID, process only appended or changed text, and benchmark updates with a long two-speaker fixture before setting a latency budget.

[MeetingStudioView.swift L98](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift#L98) · [MeetingStudioView.swift L202](https://github.com/jagdishsethuraman/Echo/blob/379f023c64c86cc14959b5c2030d8921539cb8e9/Sources/Echo/UI/MeetingStudio/MeetingStudioView.swift#L202)

## Acceptance checks before release

1. Run an end-to-end meeting with a deliberately slow local engine. Stop A, start B, then export both and compare every timestamped segment to its source. Repeat while quitting during the final sentence.
2. Run first launch on a clean account. Exercise missing engine, denied capture permission, restricted storage and interrupted recording. Each failure should identify the affected track or feature and preserve recoverable work.
3. Dictate into a native editor and a browser field. Switch focus during recognition, copy unrelated text during restore, and include an emoji. Check the destination, clipboard and saved history independently.
4. Edit a task, mark it complete, switch meetings and relaunch. Compare Studio Copy, Studio Export and history export against the same saved meeting.
5. Run a long two-channel fixture faster than the engine can drain it. Record queued audio duration, memory, finalization latency and UI update time. Use the results to set queue limits and a documented overload policy.

