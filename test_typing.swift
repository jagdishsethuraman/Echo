import AppKit
import ApplicationServices

print("Checking AXIsProcessTrusted: \(AXIsProcessTrusted())")

let testString = "Hello from Echo!"
print("Testing unicode typing logic for: \(testString)")

for char in testString.utf16 {
    if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
       let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
        var unit = char
        keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
        keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
        // print char
    }
}
print("Unicode event synthesis: OK")
