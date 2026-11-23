import AppKit
import Foundation
import Testing
@testable import Echo

private final class EventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0
    
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@Suite("HotkeyManager", .serialized)
struct HotkeyManagerTests {
    
    @MainActor @Test func runningMonitorReattachesAfterGrantAndFinishesHoldOnRevocation() async throws {
        var trusted = false
        var handlers: [(NSEvent) -> Void] = []
        var removed: [Int] = []
        let shortcuts = KeyboardShortcuts(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let manager = HotkeyManager(shortcuts: shortcuts, checkTrust: { trusted }, addGlobalMonitor: { _, handler in
            handlers.append(handler)
            return handlers.count
        }, removeGlobalMonitor: { removed.append($0 as! Int) })
        var starts = 0, finishes = 0
        manager.onKeyDown = { starts += 1 }
        manager.onKeyUp = { finishes += 1 }
        manager.startMonitoring()
        defer { manager.stopMonitoring() }
        trusted = true
        let deadline = ContinuousClock.now + .seconds(5)
        while !manager.accessibilityGranted && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(manager.accessibilityGranted)
        manager.refreshAccessibility()
        #expect(handlers.count == 2)
        #expect(removed == [1])
        let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .control,
                                     timestamp: 1, windowNumber: 0, context: nil, characters: "",
                                     charactersIgnoringModifiers: "", isARepeat: false, keyCode: 59)!
        handlers.last?(event)
        try await Task.sleep(for: .milliseconds(400))
        #expect(starts == 1)
        trusted = false
        manager.refreshAccessibility()
        #expect(finishes == 1)
        #expect(!manager.isKeyDown)
        manager.stopMonitoring()
        trusted = true
        manager.refreshAccessibility()
        #expect(handlers.count == 3)
        #expect(removed == [1, 2, 3])
    }

    @MainActor @Test func pushToTalkHoldAndRelease() async throws {
        let manager = HotkeyManager()
        let downCount = EventCounter()
        let upCount = EventCounter()
        
        manager.onKeyDown = { downCount.increment() }
        manager.onKeyUp = { upCount.increment() }
        
        // 1. Press Control
        manager.simulateFlagsChanged(flags: [.control])
        #expect(manager.isKeyDown == true)
        #expect(downCount.value == 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(downCount.value == 1)
        #expect(upCount.value == 0)
        
        // 2. Hold for 400ms (>350ms threshold) and release
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.40)
        #expect(manager.isKeyDown == false)
        #expect(upCount.value == 1)
        #expect(manager.isLocked == false)
    }
    
    @MainActor @Test func escapeCancelsPushToTalk() async throws {
        let manager = HotkeyManager()
        let downCount = EventCounter()
        let upCount = EventCounter()
        let cancelCount = EventCounter()
        
        manager.onKeyDown = { downCount.increment() }
        manager.onKeyUp = { upCount.increment() }
        manager.onCancel = { cancelCount.increment() }
        
        // 1. Press Control
        manager.simulateFlagsChanged(flags: [.control])
        #expect(manager.isKeyDown == true)
        #expect(downCount.value == 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(downCount.value == 1)
        
        // 2. Press Escape (key code 53)
        manager.simulateEscape()
        #expect(manager.isKeyDown == false)
        #expect(cancelCount.value == 1)
        #expect(upCount.value == 0)
        
        // 3. Release Control: should not trigger upCount
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.50)
        #expect(upCount.value == 0)
    }
    
    @Test func chordedKeyCancelsAndSuppressesRelease() {
        let manager = HotkeyManager()
        let downCount = EventCounter()
        let upCount = EventCounter()
        let cancelCount = EventCounter()
        
        manager.onKeyDown = { downCount.increment() }
        manager.onKeyUp = { upCount.increment() }
        manager.onCancel = { cancelCount.increment() }
        
        // 1. User presses Control (e.g. starting Ctrl+C)
        manager.simulateFlagsChanged(flags: [.control])
        #expect(manager.isKeyDown == true)
        #expect(downCount.value == 0)
        
        // 2. User presses 'C' (key code 8) while Control is down
        manager.simulateKeyDown(keyCode: 8)
        #expect(manager.isChorded == true)
        #expect(cancelCount.value == 0)
        #expect(upCount.value == 0)
        
        // 3. User releases Control
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.10)
        #expect(manager.isChorded == false)
        #expect(manager.isKeyDown == false)
        #expect(upCount.value == 0)
    }
    
    @Test func simultaneousModifiersIgnored() {
        let manager = HotkeyManager()
        let downCount = EventCounter()
        
        manager.onKeyDown = { downCount.increment() }
        
        // Control + Command chorded simultaneously
        manager.simulateFlagsChanged(flags: [.control, .command])
        #expect(manager.isKeyDown == false)
        #expect(downCount.value == 0)
        
        // Control + Option chorded simultaneously
        manager.simulateFlagsChanged(flags: [.control, .option])
        #expect(manager.isKeyDown == false)
        #expect(downCount.value == 0)
    }
    
    @MainActor @Test func quickTapDoesNotCaptureOrFinalizeAndInterveningTypingBreaksDoubleTap() async throws {
        let manager = HotkeyManager()
        var starts = 0, finishes = 0
        manager.onKeyDown = { starts += 1 }
        manager.onKeyUp = { finishes += 1 }
        manager.simulateFlagsChanged(flags: .control)
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.05)
        manager.simulateKeyDown(keyCode: 8)
        manager.simulateFlagsChanged(flags: .control, timeOffset: 0.12)
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.18)
        try await Task.sleep(for: .milliseconds(410))
        #expect(!manager.isLocked)
        #expect(starts == 0)
        #expect(finishes == 0)
    }

    @Test func escapeCancelsLockMode() {
        let manager = HotkeyManager()
        let cancelCount = EventCounter()
        let lockState = EventCounter()
        
        manager.onCancel = { cancelCount.increment() }
        manager.onLockStateChanged = { isLocked in
            if !isLocked {
                lockState.increment()
            }
        }
        
        // Manually trigger lock mode for testing
        manager.simulateFlagsChanged(flags: [.control])
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.10)
        manager.simulateFlagsChanged(flags: [.control], timeOffset: 0.15)
        #expect(!manager.isLocked)
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.20)
        #expect(manager.isLocked == true)
        
        // Press Escape while locked
        manager.simulateEscape()
        #expect(manager.isLocked == false)
        #expect(cancelCount.value == 1)
        #expect(lockState.value == 1)
    }
    
    @Test func tappingControlWhileLockedFinishes() {
        let manager = HotkeyManager()
        let upCount = EventCounter()
        let lockTransitions = EventCounter()
        
        manager.onKeyUp = { upCount.increment() }
        manager.onLockStateChanged = { _ in lockTransitions.increment() }
        
        // Enter lock mode
        manager.simulateFlagsChanged(flags: [.control])
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.10)
        manager.simulateFlagsChanged(flags: [.control], timeOffset: 0.15)
        #expect(!manager.isLocked)
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.20)
        #expect(manager.isLocked == true)
        
        // Release Control after entering lock mode
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.20)
        #expect(manager.isLocked == true)
        #expect(upCount.value == 0)
        
        // Tap Control again to stop hands-free recording
        manager.simulateFlagsChanged(flags: [.control], timeOffset: 2.0)
        manager.simulateFlagsChanged(flags: [], timeOffset: 2.1)
        #expect(manager.isLocked == false)
        #expect(upCount.value == 1)
    }

    @Test func globalMenuEquivalentShortcutsTriggerCallbacks() {
        let manager = HotkeyManager()
        let studioCount = EventCounter()
        let dictateCount = EventCounter()
        let copyCount = EventCounter()
        let meetingCount = EventCounter()

        manager.onOpenMeetingStudio = { studioCount.increment() }
        manager.onToggleDictation = { dictateCount.increment() }
        manager.onCopyLastDictation = { copyCount.increment() }
        manager.onToggleMeetingRecording = { meetingCount.increment() }

        // Test ⇧⌘E -> Meeting Studio
        manager.simulateKeyShortcut(characters: "e", modifiers: [.command, .shift])
        #expect(studioCount.value == 1)

        // Test ⇧⌘D -> Toggle Dictation
        manager.simulateKeyShortcut(characters: "d", modifiers: [.command, .shift])
        #expect(dictateCount.value == 1)

        // Test ⇧⌘C -> Copy Last Dictation
        manager.simulateKeyShortcut(characters: "c", modifiers: [.command, .shift])
        #expect(copyCount.value == 1)

        // Test ⇧⌘R -> Start/Stop Meeting
        manager.simulateKeyShortcut(characters: "r", modifiers: [.command, .shift])
        #expect(meetingCount.value == 1)
    }

    @Test func focusedAppShortcutsAreHandledOnce() {
        let manager = HotkeyManager()
        let dictateCount = EventCounter()
        let meetingCount = EventCounter()
        manager.onToggleDictation = { dictateCount.increment() }
        manager.onToggleMeetingRecording = { meetingCount.increment() }

        manager.simulateLocalKeyShortcut(characters: "d", modifiers: [.command, .shift])
        manager.simulateLocalKeyShortcut(characters: "r", modifiers: [.command, .shift])
        #expect(dictateCount.value == 1)
        #expect(meetingCount.value == 1)
    }
}
