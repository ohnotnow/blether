import SwiftUI

/// The persona list (shared by every profile), then the profile being edited, then for each role (in
/// heard order) which persona writes the words and which voice speaks them, in that profile.
/// Voices load once, off the render path; there are about 180 of them.
struct VoicesSection: View {
    @Bindable var settings: AppSettings
    let provider: any Provider
    @State private var voices: [Voice] = []
    @State private var voicesFailed = false
    @State private var editing: PersonaEditor.Mode?
    /// Empty until `.task` runs; settings are not read while the view is being built.
    @State private var editingProfileID = ""
    /// The name field's text. Kept apart from the model so a trailing space survives while typing.
    @State private var nameDraft = ""

    var body: some View {
        Section {
            personaRows
            profileRows
            ForEach(Role.allCases, id: \.self) { role in
                rolePickers(role)
            }
        } header: {
            Text("Profiles, voices and personas")
        } footer: {
            if voicesFailed { Text("Could not load voices") }
        }
        .task {
            select(settings.defaultProfileID)
            do { voices = try await provider.voices() } catch { voicesFailed = true }
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

    // MARK: - Profiles

    /// The profile whose roles the pickers below edit. Falls back to the default when the selected
    /// one has just been deleted.
    private var editingProfile: Profile {
        settings.profiles.first { $0.id == editingProfileID } ?? settings.defaultProfile
    }

    private var isEditingDefault: Bool { editingProfile.id == settings.defaultProfileID }

    @ViewBuilder
    private var profileRows: some View {
        Picker("Profile", selection: Binding(get: { editingProfile.id }, set: { select($0) })) {
            ForEach(settings.profiles) { profile in
                Text(profile.name).tag(profile.id)
            }
        }
        TextField("Profile name", text: $nameDraft)
            .onChange(of: nameDraft) { _, name in settings.renameProfile(id: editingProfile.id, name: name) }
        Toggle(isOn: Binding(get: { isEditingDefault }, set: { if $0 { settings.defaultProfileID = editingProfile.id } })) {
            VStack(alignment: .leading) {
                Text("Default profile")
                Text("Used when a hook names no profile, or one that does not exist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isEditingDefault)
        HStack {
            Button("Add profile") { select(settings.addProfile(name: "New profile").id) }
            Button("Delete profile", role: .destructive) {
                settings.deleteProfile(id: editingProfile.id)
                select(settings.defaultProfileID)
            }
            .disabled(settings.profiles.count == 1)
            .accessibilityLabel("Delete profile \(editingProfile.name)")
        }
        Text("Hooks pick this profile with ?profile=\(Self.queryValue(editingProfile.name)) on the hook URL.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func select(_ id: String) {
        editingProfileID = id
        nameDraft = editingProfile.name
    }

    /// The name as it goes in a URL query. `.urlQueryAllowed` leaves `&`, `=` and `+` alone, and each
    /// of those would change the meaning, so they are escaped by hand.
    static func queryValue(_ name: String) -> String {
        (name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)
            .replacingOccurrences(of: "&", with: "%26")
            .replacingOccurrences(of: "=", with: "%3D")
            .replacingOccurrences(of: "+", with: "%2B")
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

    /// Reads and writes one field of a role in the profile being edited. A role missing from the stored
    /// dictionary (a new role added after settings were first saved) starts from the defaults.
    private func binding<V>(for role: Role, _ keyPath: WritableKeyPath<RoleSettings, V>) -> Binding<V> {
        Binding(
            get: { (editingProfile.roles[role] ?? Self.fallback())[keyPath: keyPath] },
            set: { value in
                var roles = editingProfile.roles
                var entry = roles[role] ?? Self.fallback()
                entry[keyPath: keyPath] = value
                roles[role] = entry
                settings.updateRoles(roles, in: editingProfile.id)
            }
        )
    }

    private static func fallback() -> RoleSettings {
        RoleSettings(personaID: nil, voiceID: KokoroProvider.defaultVoiceID)
    }
}
