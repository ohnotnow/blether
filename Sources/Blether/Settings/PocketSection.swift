import SwiftUI
import UniformTypeIdentifiers

/// Pocket's settings on the TTS Providers page: the voices a person added from a `.safetensors` file
/// made with training/pocket_clone.py. Adding or removing one restarts the Pocket helper so the
/// pickers see it, rather than relaunching blether, which would close every channel.
struct PocketSection: View {
    let registry: ProviderRegistry
    private let store = PocketVoices()
    @State private var ids: [String] = []
    @State private var importing = false
    /// The file chosen, waiting for a name.
    @State private var picked: URL?
    @State private var nameDraft = ""
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(ids, id: \.self) { id in
                LabeledContent(PocketVoices.displayName(id: id)) {
                    Button("Remove", role: .destructive) { change { try store.remove(id: id) } }
                        .accessibilityLabel("Remove \(PocketVoices.displayName(id: id))")
                }
                .focusable()
            }
            Button("Add a voice…") { importing = true }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Pocket voices")
        } footer: {
            Text("Make a voice from a clip of speech with pocket_clone.py; [its README](https://github.com/ohnotnow/blether/tree/master/training) explains the one-off Hugging Face step. Added voices are listed first in a profile's voice picker, where Play lets you hear them.")
        }
        .task { ids = store.ids }
        .fileImporter(isPresented: $importing, allowedContentTypes: [Self.safetensors]) { result in
            switch result {
            case .success(let url):
                nameDraft = PocketVoices.displayName(id: PocketVoices.id(for: url.deletingPathExtension().lastPathComponent))
                picked = url
            case .failure(let failure):
                error = "Could not open the file: \(failure.localizedDescription)"
            }
        }
        .alert("Name this voice", isPresented: Binding(get: { picked != nil }, set: { if !$0 { picked = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("Add") {
                guard let url = picked else { return }
                change {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try store.add(url, name: nameDraft)
                }
            }
            .disabled(PocketVoices.id(for: nameDraft).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Profiles show the voice by this name. An added voice with the same name is replaced.")
        }
    }

    private static let safetensors = UTType(filenameExtension: "safetensors") ?? .data

    /// Runs one add or remove, then lists the folder again and restarts the helper so it does too.
    private func change(_ body: () throws -> Void) {
        do {
            try body()
            error = nil
        } catch {
            self.error = "Could not change the Pocket voices: \(error.localizedDescription)"
        }
        ids = store.ids
        if let pocket = registry.provider(id: "pocket") as? PocketProvider {
            Task { await pocket.reload() }
        }
    }
}
