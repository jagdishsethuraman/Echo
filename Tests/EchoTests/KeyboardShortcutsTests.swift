import AppKit
import Testing
@testable import Echo

@Suite("Configurable Keyboard Shortcuts")
struct KeyboardShortcutsTests {
    private func withStore(_ test: (KeyboardShortcuts, UserDefaults) throws -> Void) rethrows {
        let name = "echo-shortcuts-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try test(KeyboardShortcuts(defaults: defaults), defaults)
    }

    @Test func savesRestoresAndRejectsConflictsAtomically() {
        withStore { store, defaults in
            var draft = store.bindings
            draft[.meeting] = EchoShortcut([.control, .option], "m")
            store.save(draft)
            #expect(KeyboardShortcuts(defaults: defaults).bindings == draft)
            draft[.copy] = draft[.meeting]
            #expect(KeyboardShortcuts.validationError(draft) != nil)
            store.save(draft)
            #expect(store[.copy] == ShortcutAction.copy.initial)
            store.save(KeyboardShortcuts.initial)
            #expect(KeyboardShortcuts(defaults: defaults).bindings == KeyboardShortcuts.initial)
        }
    }

    private func event(_ type: NSEvent.EventType, key: String = "k", flags: NSEvent.ModifierFlags = [.option, .control], time: Double, repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: time,
                         windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                         isARepeat: repeatKey, keyCode: 40)!
    }

    @Test func customHoldTracksKeyUpRepeatAndEarlyModifierRelease() {
        withStore { store, _ in
            let manager = HotkeyManager(shortcuts: store)
            var draft = store.bindings
            draft[.pushToTalk] = EchoShortcut([.option, .control], "k")
            store.save(draft)
            var starts = 0, finishes = 0
            manager.onKeyDown = { starts += 1 }
            manager.onKeyUp = { finishes += 1 }
            manager.simulateFlagsChanged(flags: [.control, .option])
            #expect(starts == 0)
            manager.routeKeyEvent(event(.keyDown, time: 1000))
            manager.routeKeyEvent(event(.keyDown, time: 1000.1, repeatKey: true))
            manager.routeKeyEvent(event(.keyUp, time: 1000.5))
            manager.routeKeyEvent(event(.keyDown, time: 1001))
            manager.simulateFlagsChanged(flags: .control, timeOffset: 1.5)
            manager.routeKeyEvent(event(.keyUp, time: 1001.6))
            #expect(starts == 2)
            #expect(finishes == 2)
        }
    }

    @Test func modifierOnlyBindingAndCustomCommandUseExactModifiers() {
        withStore { store, _ in
            let manager = HotkeyManager(shortcuts: store)
            var draft = store.bindings
            draft[.pushToTalk] = EchoShortcut([.option, .shift])
            draft[.meeting] = EchoShortcut([.control, .option], "k")
            store.save(draft)
            var meetings = 0
            manager.onToggleMeetingRecording = { meetings += 1 }
            manager.simulateFlagsChanged(flags: .option)
            #expect(!manager.isKeyDown)
            manager.simulateFlagsChanged(flags: [.option, .shift])
            #expect(manager.isKeyDown)
            manager.simulateFlagsChanged(flags: .shift, timeOffset: 0.5)
            #expect(!manager.isKeyDown)
            manager.simulateKeyShortcut(characters: "r", modifiers: [.command, .shift])
            manager.routeKeyEvent(event(.keyDown, flags: [.control, .option, .shift], time: 1001))
            manager.routeKeyEvent(event(.keyDown, time: 1002))
            manager.routeKeyEvent(event(.keyDown, time: 1002.1, repeatKey: true))
            #expect(meetings == 1)
        }
    }
}
