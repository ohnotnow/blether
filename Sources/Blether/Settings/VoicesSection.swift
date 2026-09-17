import SwiftUI

/// The persona list, then for each role (in heard order) which persona writes the words and which
/// voice speaks them. Voices load once, off the render path; there are about 180 of them.
struct VoicesSection: View {
    @Bindable var settings: AppSettings
    @State private var voices: [Voice] = []
    @State private var voicesFailed = false
    @State private var editing: PersonaEditor.Mode?

    var body: some View {
        Section {
            personaRows
            ForEach(Role.allCases, id: \.self) { role in
                rolePickers(role)
            }
        } header: {
            Text("Voices and personas")
        } footer: {
            if voicesFailed { Text("Could not load voices") }
        }
        .task {
            do { voices = try await AppleVoicesProvider().voices() } catch { voicesFailed = true }
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

    // MARK: - Personas

    @ViewBuilder
    private var personaRows: some View {
        ForEach(settings.personas) { persona in
            LabeledContent(persona.name) {
                Button("Edit") { editing = .edit(persona) }
                    .accessibilityLabel("Edit \(persona.name)")
                Button("Delete", role: .destructive) { settings.deletePersona(id: persona.id) }
                    .accessibilityLabel("Delete \(persona.name)")
            }
            .focusable()
        }
        HStack {
            Button("Add persona") { editing = .add }
            if !settings.personas.contains(where: { $0.id == Persona.marvin.id }) {
                Button("Restore Marvin") { settings.personas.append(Persona.marvin) }
            }
        }
    }

    // MARK: - Roles

    private func rolePickers(_ role: Role) -> some View {
        Group {
            Picker("\(role.displayName) persona", selection: binding(for: role, \.personaID)) {
                Text("None").tag(String?.none)
                ForEach(settings.personas) { persona in
                    Text(persona.name).tag(Optional(persona.id))
                }
            }
            Picker("\(role.displayName) voice", selection: binding(for: role, \.voiceID)) {
                let stored = binding(for: role, \.voiceID).wrappedValue
                if !voices.isEmpty, !voices.contains(where: { $0.id == stored }) {
                    // The stored voice has gone from this Mac; name it so the picker is never blank.
                    Text("Unavailable voice").tag(stored)
                }
                ForEach(languages, id: \.self) { language in
                    Section(Self.languageName(language)) {
                        ForEach(voices.filter { $0.language == language }, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                }
            }
        }
    }

    private var languages: [String] {
        Array(Set(voices.map(\.language))).sorted()
    }

    /// "en-GB" reads as "English (United Kingdom)"; an unknown code falls back to itself.
    private static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// Reads and writes one field of a role through `settings.roles`. A role missing from the stored
    /// dictionary (a new role added after settings were first saved) starts from the defaults.
    private func binding<V>(for role: Role, _ keyPath: WritableKeyPath<RoleSettings, V>) -> Binding<V> {
        Binding(
            get: { (settings.roles[role] ?? Self.fallback())[keyPath: keyPath] },
            set: { value in
                var roles = settings.roles
                var entry = roles[role] ?? Self.fallback()
                entry[keyPath: keyPath] = value
                roles[role] = entry
                settings.roles = roles
            }
        )
    }

    private static func fallback() -> RoleSettings {
        RoleSettings(personaID: nil, voiceID: AppleVoicesProvider.defaultVoiceID())
    }
}
