import SwiftUI

/// The profile being edited with its provider, then for each role (in heard order) which persona
/// writes the words and which voice speaks them, in that profile. Personas themselves are edited on
/// their own page (PersonasSection). Each provider's voices load once per window, off the render path, when a profile using
/// it is first shown; a list that is empty or failed turns the voice pickers into typed-id fields.
struct VoicesSection: View {
    @Bindable var settings: AppSettings
    let registry: ProviderRegistry
    @State private var voicesByProvider: [String: [Voice]] = [:]
    @State private var voiceErrors: [String: String] = [:]
    /// Empty until `.task` runs; settings are not read while the view is being built.
    @State private var editingProfileID = ""
    /// The name field's text. Kept apart from the model so a trailing space survives while typing.
    @State private var nameDraft = ""
    /// Set after Add so the person is already typing the new name.
    @FocusState private var nameFocused: Bool
    /// One per window; it caches on disk, so a window's life is the right scope.
    @State private var sampler: VoiceSampler?
    @State private var sampleError: [Role: String] = [:]
    @State private var sampling: Role?

    var body: some View {
        Section {
            profilePicker
        }
        Section {
            profileRows
        }
        ForEach(Role.allCases, id: \.self) { role in
            Section(role.displayName) {
                rolePickers(role)
            }
        }
        .task {
            select(settings.defaultProfileID)
            sampler = VoiceSampler(registry: registry)
        }
        .task(id: editingProvider.name) {
            await loadVoices(for: editingProvider)
        }
    }

    // MARK: - Profiles

    /// The profile whose roles the pickers below edit. Falls back to the default when the selected
    /// one has just been deleted.
    private var editingProfile: Profile {
        settings.profiles.first { $0.id == editingProfileID } ?? settings.defaultProfile
    }

    private var isEditingDefault: Bool { editingProfile.id == settings.defaultProfileID }

    private var editingProvider: any Provider { registry.provider(id: editingProfile.providerID) }

    private var voices: [Voice] { voicesByProvider[editingProvider.name] ?? [] }

    /// Once per provider per window, until Retry clears the entry. A failure is shown at each voice row.
    private func loadVoices(for provider: any Provider) async {
        guard voicesByProvider[provider.name] == nil else { return }
        do {
            voicesByProvider[provider.name] = try await provider.voices()
            voiceErrors[provider.name] = nil
        } catch {
            voicesByProvider[provider.name] = []
            voiceErrors[provider.name] = "Could not load \(ProviderRegistry.displayName(id: provider.name)) voices: \(error)"
        }
    }

    /// Which profile the rest of the page edits, with add and delete beside it.
    private var profilePicker: some View {
        HStack {
            Picker("Profile", selection: Binding(get: { editingProfile.id }, set: { select($0) })) {
                ForEach(settings.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            Button {
                select(settings.addProfile(name: "New profile").id)
                nameFocused = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20)
            }
            .accessibilityLabel("Add profile")
            .help("Add profile")
            Button(role: .destructive) {
                settings.deleteProfile(id: editingProfile.id)
                select(settings.defaultProfileID)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 20)
            }
            .disabled(settings.profiles.count == 1)
            .accessibilityLabel("Delete profile \(editingProfile.name)")
            .help("Delete profile")
        }
    }

    /// True while the name field holds a name another profile already has; the store refuses it.
    private var nameIsTaken: Bool { settings.isProfileNameTaken(nameDraft, excluding: editingProfile.id) }

    @ViewBuilder
    private var profileRows: some View {
        TextField("Name", text: $nameDraft)
            .focused($nameFocused)
            .onChange(of: nameDraft) { _, name in settings.renameProfile(id: editingProfile.id, name: name) }
        if nameIsTaken {
            Text("Another profile is already called \(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)); the name is not saved.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
        Picker("TTS provider", selection: Binding(get: { editingProvider.name }, set: { settings.setProvider(id: $0, in: editingProfile.id) })) {
            ForEach(registry.ids, id: \.self) { id in
                Text(ProviderRegistry.displayName(id: id)).tag(id)
            }
        }
        Toggle(isOn: Binding(get: { isEditingDefault }, set: { if $0 { settings.defaultProfileID = editingProfile.id } })) {
            VStack(alignment: .leading) {
                Text("Default")
                Text("Used when a hook names no profile, or one that does not exist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isEditingDefault)
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

    /// The persona, the voice picker when the provider's list loaded, and always a typed-id field, so an
    /// id the list does not carry (a shared ElevenLabs voice, a Mistral slug) can be entered. Picker and
    /// field share one binding. A failed or empty list says so here, at the row, with a Retry.
    @ViewBuilder
    private func rolePickers(_ role: Role) -> some View {
        Picker("Persona", selection: binding(for: role, \.personaID)) {
            Text("None").tag(String?.none)
            ForEach(settings.personas) { persona in
                Text(persona.name).tag(Optional(persona.id))
            }
        }
        if !voices.isEmpty {
            Picker("Voice", selection: binding(for: role, \.voiceID)) {
                let stored = binding(for: role, \.voiceID).wrappedValue
                if !voices.contains(where: { $0.id == stored }) {
                    // The stored voice is not in this provider's list; name it so the picker is never blank.
                    Text("Unavailable voice (\(stored))").tag(stored)
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
        HStack {
            TextField("Voice id", text: binding(for: role, \.voiceID))
                .accessibilityLabel("\(role.displayName) voice id")
            playButton(role)
        }
        if let error = sampleError[role] {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        }
        if let error = voiceErrors[editingProvider.name] {
            HStack(alignment: .firstTextBaseline) {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { retryVoices() }
                    .accessibilityLabel("Retry loading \(ProviderRegistry.displayName(id: editingProvider.name)) voices")
            }
        } else if voices.isEmpty {
            Text("No voices listed for \(ProviderRegistry.displayName(id: editingProvider.name)); type a voice id.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Speaks the sample line in this role's voice; Stop while it plays. Disabled while synthesising.
    private func playButton(_ role: Role) -> some View {
        let voiceID = binding(for: role, \.voiceID).wrappedValue
        let name = voices.first { $0.id == voiceID }?.name ?? voiceID
        let playing = sampler?.isPlaying == true && sampling == role
        return Button(playing ? "Stop" : "Play") {
            if playing {
                sampler?.stop()
                sampling = nil
                return
            }
            sampling = role
            sampleError[role] = nil
            Task {
                do {
                    try await sampler?.play(providerID: editingProvider.name, voiceID: voiceID, name: name)
                } catch {
                    sampleError[role] = "Could not play a sample: \(error)"
                    sampling = nil
                }
            }
        }
        .disabled(voiceID.trimmingCharacters(in: .whitespaces).isEmpty || (sampler?.inFlight.isEmpty == false))
        .accessibilityLabel(playing ? "Stop the sample of \(name)" : "Play a sample of \(name)")
    }

    private func retryVoices() {
        let provider = editingProvider
        voicesByProvider[provider.name] = nil
        voiceErrors[provider.name] = nil
        Task { await loadVoices(for: provider) }
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
