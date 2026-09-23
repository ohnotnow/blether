import SwiftUI

/// Breeze's settings on the TTS Providers page: the one quality switch and the voice designs,
/// managed like personas. Profiles pick a design per role like any other voice (blether-WtzbG).
struct BreezeSection: View {
    @Bindable var settings: AppSettings
    @State private var editing: DescriptionEditor.Mode?

    /// From what made the four defaults work, heard on 2026-09-22 (blether-gzXn6).
    static let designHelp = "Describe the voice itself, not just the character: sex, age, accent, pitch and texture, then how they speak and their mood. A role or setting helps with the feel, for example “police detective in a bleak Nordic crime drama”. The more detail, the more the voice stays the same from clip to clip. Words like “slow”, “hesitant” or “pauses” make clips longer, and so slower to make."

    var body: some View {
        Section {
            Picker("Quality", selection: $settings.breezeQuality) {
                ForEach(BreezeQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            Text("Better sounds noticeably richer and takes about twice as long to make.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Breeze")
        }
        Section {
            ForEach(settings.voiceDesigns) { design in
                LabeledContent {
                    Button("Edit") { editing = .edit(id: design.id, name: design.name, description: design.description) }
                        .accessibilityLabel("Edit \(design.name)")
                    Button("Delete", role: .destructive) { settings.deleteVoiceDesign(id: design.id) }
                        .accessibilityLabel("Delete \(design.name)")
                } label: {
                    Text(design.name)
                    Text(design.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .focusable()
            }
            HStack {
                Button("Add voice design") { editing = .add }
                if !missingDefaults.isEmpty {
                    Button("Restore the defaults") { settings.voiceDesigns += missingDefaults }
                        .accessibilityLabel("Restore the default voice designs that were deleted")
                }
            }
        } header: {
            Text("Breeze voice designs")
        } footer: {
            Text("Breeze builds a voice from a written description. It runs on this Mac, and the first use downloads about 2.3 GB. A profile picks a design for each role, like any other voice.")
        }
        .sheet(item: $editing) { mode in
            DescriptionEditor(mode: mode, help: Self.designHelp) { name, description in
                switch mode {
                case .add: settings.addVoiceDesign(name: name, description: description)
                case .edit(let id, _, _): settings.updateVoiceDesign(VoiceDesign(id: id, name: name, description: description))
                }
            }
        }
    }

    private var missingDefaults: [VoiceDesign] {
        let ids = Set(settings.voiceDesigns.map(\.id))
        return VoiceDesign.defaults.filter { !ids.contains($0.id) }
    }
}
