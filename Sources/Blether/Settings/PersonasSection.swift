import SwiftUI

/// The persona list, shared by every profile, and the sheet that adds or edits one.
struct PersonasSection: View {
    @Bindable var settings: AppSettings
    @State private var editing: PersonaEditor.Mode?

    var body: some View {
        Section {
            ForEach(settings.personas) { persona in
                LabeledContent {
                    Button("Edit") { editing = .edit(persona) }
                        .accessibilityLabel("Edit \(persona.name)")
                    Button("Delete", role: .destructive) { settings.deletePersona(id: persona.id) }
                        .accessibilityLabel("Delete \(persona.name)")
                } label: {
                    Text(persona.name)
                    // A reminder of which one was told to be sarcastic, without opening it.
                    Text(persona.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .focusable()
            }
            HStack {
                Button("Add persona") { editing = .add }
                if !settings.personas.contains(where: { $0.id == Persona.marvin.id }) {
                    Button("Restore Marvin") { settings.personas.append(Persona.marvin) }
                }
            }
        } footer: {
            Text("A persona writes the words; a profile picks which persona speaks in each role.")
        }
        .sheet(item: $editing) { mode in
            PersonaEditor(mode: mode) { name, description in
                switch mode {
                case .add: settings.addPersona(name: name, description: description)
                case .edit(let persona): settings.updatePersona(Persona(id: persona.id, name: name, description: description))
                }
            }
        }
    }
}
