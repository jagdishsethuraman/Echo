import AppKit

enum ShortcutAction: String, CaseIterable, Codable {
    case pushToTalk, studio, dictation, copy, meeting, export

    var title: String {
        switch self {
        case .pushToTalk: return "Push to Talk"
        case .studio: return "Open Meeting Studio"
        case .dictation: return "Toggle Dictation"
        case .copy: return "Copy Last Dictation"
        case .meeting: return "Start or Stop Meeting"
        case .export: return "Export Current Meeting"
        }
    }

    var initial: EchoShortcut {
        let key: String
        switch self {
        case .pushToTalk: return EchoShortcut(.control)
        case .studio: key = "e"
        case .dictation: key = "d"
        case .copy: key = "c"
        case .meeting: key = "r"
        case .export: return EchoShortcut([])
        }
        return EchoShortcut([.shift, .command], key)
    }
}

struct EchoShortcut: Codable, Equatable, Hashable {
    var modifiers: UInt
    var key: String
    static let supported: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    static let keys = Array("abcdefghijklmnopqrstuvwxyz0123456789 ").map(String.init)
    static let symbols: [(NSEvent.ModifierFlags, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")
    ]
    var flags: NSEvent.ModifierFlags { .init(rawValue: modifiers) }
    var label: String {
        let prefix = Self.symbols.filter { flags.contains($0.0) }.map(\.1).joined()
        return prefix + (key == " " ? "Space" : key.uppercased())
    }

    init(_ flags: NSEvent.ModifierFlags, _ key: String = "") {
        modifiers = flags.rawValue
        self.key = key
    }

    func matches(_ event: NSEvent) -> Bool {
        guard !key.isEmpty, flags == event.modifierFlags.intersection(Self.supported) else { return false }
        let stripped = event.charactersIgnoringModifiers?.lowercased()
        let character = stripped.flatMap { Self.keys.contains($0) ? $0 : nil } ?? event.characters(byApplyingModifiers: [])
        return character?.lowercased() == key
    }
}

final class KeyboardShortcuts: ObservableObject {
    typealias Bindings = [ShortcutAction: EchoShortcut]
    static let shared = KeyboardShortcuts()
    static let initial = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.initial) })
    private let defaults: UserDefaults
    private let storageKey = "echo.keyboardShortcuts.v1"
    @Published private(set) var bindings: Bindings
    subscript(_ action: ShortcutAction) -> EchoShortcut { bindings[action] ?? action.initial }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var values = Self.initial
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Bindings.self, from: data) {
            values.merge(saved) { _, saved in saved }
        }
        bindings = Self.validationError(values) == nil ? values : Self.initial
    }

    static func validationError(_ values: Bindings) -> String? {
        var used = [EchoShortcut: ShortcutAction]()
        for action in ShortcutAction.allCases {
            let binding = values[action] ?? action.initial
            if binding == EchoShortcut([]), action == .export { continue }
            guard !binding.flags.isEmpty, binding.flags.isSubset(of: EchoShortcut.supported),
                  binding.key.isEmpty ? action == .pushToTalk : EchoShortcut.keys.contains(binding.key) else {
                return "Choose a modifier and a valid key for " + action.title + "."
            }
            if binding.flags == .shift {
                return "Add Control, Option or Command so Shift remains available for typing."
            }
            if binding == EchoShortcut(.command, "q") { return "⌘Q is used by Quit Echo." }
            if let other = used[binding] { return action.title + " uses the same shortcut as " + other.title + "." }
            used[binding] = action
        }
        return nil
    }

    func save(_ values: Bindings) {
        guard Self.validationError(values) == nil, let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: storageKey)
        bindings = values
    }
}
