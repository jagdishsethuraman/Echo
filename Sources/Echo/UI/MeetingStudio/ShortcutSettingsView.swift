import SwiftUI

struct ShortcutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = KeyboardShortcuts.shared.bindings
    private let modifiers = (1..<16).map { mask in
        EchoShortcut.symbols.enumerated().reduce(into: NSEvent.ModifierFlags()) { flags, pair in
            if mask & (1 << pair.offset) != 0 { flags.insert(pair.element.0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts").font(.title2.bold())
            Text("Hold for 0.3 seconds to dictate. A single tap does nothing. Double-tap to speak hands-free, then tap once to finish.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow { Text("Action"); Text("Modifiers"); Text("Key") }.font(.headline)
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    GridRow {
                        Text(action.title)
                        Picker(action.title + " modifiers", selection: binding(action, \.modifiers)) {
                            if action == .export { Text("None").tag(UInt(0)) }
                            ForEach(modifiers, id: \.rawValue) { flags in
                                Text(EchoShortcut(flags).label).tag(flags.rawValue)
                            }
                        }.labelsHidden()
                        Picker(action.title + " key", selection: binding(action, \.key)) {
                            if action == .pushToTalk || action == .export { Text("None").tag("") }
                            ForEach(EchoShortcut.keys, id: \.self) { key in
                                Text(key == " " ? "Space" : key.uppercased()).tag(key)
                            }
                        }.labelsHidden()
                    }
                }
            }
            if let error = KeyboardShortcuts.validationError(draft) {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                Button("Restore Defaults") { draft = KeyboardShortcuts.initial }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    KeyboardShortcuts.shared.save(draft)
                    MenuBarManager.shared.rebuildMenu()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(KeyboardShortcuts.validationError(draft) != nil)
            }
        }
        .padding(24).frame(width: 500)
    }

    private func binding<T>(_ action: ShortcutAction, _ path: WritableKeyPath<EchoShortcut, T>) -> Binding<T> {
        Binding(get: { (draft[action] ?? action.initial)[keyPath: path] },
                set: { draft[action, default: action.initial][keyPath: path] = $0 })
    }
}
