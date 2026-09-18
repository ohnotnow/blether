import SwiftUI

/// One key row per API provider. Kokoro runs locally and has no row.
struct ProvidersSection: View {
    @Bindable var settings: AppSettings
    let registry: ProviderRegistry

    var body: some View {
        Section {
            ForEach(registry.ids.filter { $0 != ProviderRegistry.defaultID }, id: \.self) { id in
                APIKeyRows(
                    title: ProviderRegistry.displayName(id: id),
                    hasKey: settings.hasAPIKey(for: id),
                    save: { settings.setAPIKey($0, for: id) },
                    remove: { settings.setAPIKey(nil, for: id) }
                )
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("Keys stay in your macOS Keychain and are sent only to that service. Kokoro runs locally and needs none. Each profile below picks which provider speaks it.")
        }
    }
}
