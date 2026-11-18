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
    
    @Test func pushToTalkHoldAndRelease() async {
        let manager = HotkeyManager()
        let downCount = EventCounter()
        let upCount = EventCounter()
        
        manager.onKeyDown = { downCount.increment() }
        manager.onKeyUp = { upCount.increment() }
        
        // 1. Press Control
        manager.simulateFlagsChanged(flags: [.control])
        #expect(manager.isKeyDown == true)
        #expect(downCount.value == 1)
        #expect(upCount.value == 0)
        
        // 2. Hold for 400ms (>350ms threshold) and release
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.40)
        #expect(manager.isKeyDown == false)
        #expect(upCount.value == 1)
        #expect(manager.isLocked == false)
    }
    
    @Test func escapeCancelsPushToTalk() {
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
        #expect(downCount.value == 1)
        
        // 2. User presses 'C' (key code 8) while Control is down
        manager.simulateKeyDown(keyCode: 8)
        #expect(manager.isChorded == true)
        #expect(cancelCount.value == 1)
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
        #expect(manager.isLocked == true)
        
        // Release Control after entering lock mode
        manager.simulateFlagsChanged(flags: [], timeOffset: 0.20)
        #expect(manager.isLocked == true)
        #expect(upCount.value == 0)
        
        // Tap Control again to stop hands-free recording
        manager.simulateFlagsChanged(flags: [.control], timeOffset: 2.0)
        #expect(manager.isLocked == false)
        #expect(upCount.value == 1)
    }
}
