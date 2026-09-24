import SwiftUI

/// One key row per Keychain account, so providers that share a key (OpenRouter's) share a row.
/// Kokoro, Breeze and Pocket run locally and have no row.
struct ProvidersSection: View {
    @Bindable var settings: AppSettings
    let registry: ProviderRegistry

    var body: some View {
        Section {
            ForEach(registry.keyAccounts, id: \.self) { account in
                APIKeyRows(
                    title: ProviderRegistry.displayName(id: account),
                    hasKey: settings.hasAPIKey(for: account),
                    save: { settings.setAPIKey($0, for: account) },
                    remove: { settings.setAPIKey(nil, for: account) }
                )
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("Keys stay in your macOS Keychain and are sent only to that service. Kokoro, Breeze and Pocket run locally and need none. Each profile picks which provider speaks it.")
        }
    }
}
