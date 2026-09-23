import SwiftUI

/// Breeze's settings on the TTS Providers page: the voice designs, each with its own quality,
/// managed like personas. Profiles pick a design per role like any other voice (blether-WtzbG).
struct BreezeSection: View {
    @Bindable var settings: AppSettings
    @State private var editing: DescriptionEditor.Mode?

    /// From what made the four defaults work, heard on 2026-09-22 (blether-gzXn6).
    static let designHelp = "Describe the voice itself, not just the character: sex, age, accent, pitch and texture, then how they speak and their mood. A role or setting helps with the feel, for example “police detective in a bleak Nordic crime drama”. The more detail, the more the voice stays the same from clip to clip. Words like “slow”, “hesitant” or “pauses” make clips longer, and so slower to make."

    var body: some View {
        Section {
            ForEach(settings.voiceDesigns) { design in
                LabeledContent {
                    Button("Edit") { editing = .edit(id: design.id, name: design.name, description: design.description) }
                        .accessibilityLabel("Edit \(design.name)")
                    Button("Delete", role: .destructive) { settings.deleteVoiceDesign(id: design.id) }
                        .accessibilityLabel("Delete \(design.name)")
                } label: {
                    Text(design.name)
                    Text("\(design.quality.displayName): \(design.description)")
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
            DescriptionEditor(mode: mode, help: Self.designHelp, quality: quality(for: mode)) { name, description, quality in
                let quality = quality ?? .better
                switch mode {
                case .add: settings.addVoiceDesign(name: name, description: description, quality: quality)
                case .edit(let id, _, _): settings.updateVoiceDesign(VoiceDesign(id: id, name: name, description: description, quality: quality))
                }
            }
        }
    }

    /// A new design starts at Better; an edited one keeps its own.
    private func quality(for mode: DescriptionEditor.Mode) -> BreezeQuality {
        guard case .edit(let id, _, _) = mode else { return .better }
        return settings.voiceDesigns.first { $0.id == id }?.quality ?? .better
    }

    private var missingDefaults: [VoiceDesign] {
        let ids = Set(settings.voiceDesigns.map(\.id))
        return VoiceDesign.defaults.filter { !ids.contains($0.id) }
    }
}
