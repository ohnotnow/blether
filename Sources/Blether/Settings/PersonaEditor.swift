import SwiftUI

/// One sheet for adding and editing a persona. Save hands back trimmed strings; the store does the rest.
struct PersonaEditor: View {
    enum Mode: Identifiable {
        case add
        case edit(Persona)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let persona): persona.id
            }
        }
    }

    let mode: Mode
    let onSave: (_ name: String, _ description: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String

    init(mode: Mode, onSave: @escaping (_ name: String, _ description: String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let persona) = mode {
            _name = State(initialValue: persona.name)
            _description = State(initialValue: persona.description)
        } else {
            _name = State(initialValue: "")
            _description = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(3...)
            Text("A noun phrase that finishes the sentence “in the voice of…”, so no full stop.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(saveTitle) {
                    onSave(trimmed(name), trimmed(description))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(name).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 260)
    }

    private var saveTitle: String {
        if case .add = mode { "Add" } else { "Save" }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
