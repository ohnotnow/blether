import SwiftUI

/// One sheet for adding and editing a named description: a persona or a Breeze voice design. Save
/// hands back trimmed strings; the store does the rest.
struct DescriptionEditor: View {
    enum Mode: Identifiable {
        case add
        case edit(id: String, name: String, description: String)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let id, _, _): id
            }
        }
    }

    let mode: Mode
    /// Shown under the description: how to write one.
    let help: String
    let onSave: (_ name: String, _ description: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String

    init(mode: Mode, help: String, onSave: @escaping (_ name: String, _ description: String) -> Void) {
        self.mode = mode
        self.help = help
        self.onSave = onSave
        if case .edit(_, let name, let description) = mode {
            _name = State(initialValue: name)
            _description = State(initialValue: description)
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
            Text(help)
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
