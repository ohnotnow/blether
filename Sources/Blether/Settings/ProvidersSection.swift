import SwiftUI

/// One key row per API provider. Kokoro and Breeze run locally and have no row.
struct ProvidersSection: View {
    @Bindable var settings: AppSettings
    let registry: ProviderRegistry

    var body: some View {
        Section {
            ForEach(registry.ids.filter { !ProviderRegistry.localIDs.contains($0) }, id: \.self) { id in
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
            Text("Keys stay in your macOS Keychain and are sent only to that service. Kokoro and Breeze run locally and need none. Each profile picks which provider speaks it.")
        }
    }
}
