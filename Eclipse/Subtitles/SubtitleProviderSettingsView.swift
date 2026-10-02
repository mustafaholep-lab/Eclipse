import SwiftUI

struct SubtitleProviderSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("Direct subtitle services are optional. Add your own API credentials and test them before enabling a service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(DirectSubtitleProviderKind.allCases, id: \.rawValue) { provider in
                SubtitleProviderCredentialSection(provider: provider)
            }
        }
        .navigationTitle("Subtitle Providers")
    }
}

private struct SubtitleProviderCredentialSection: View {
    let provider: DirectSubtitleProviderKind
    @State private var apiKey = ""
    @State private var bearerToken = ""
    @State private var enabled = false
    @State private var hasSavedKey = false
    @State private var isTesting = false
    @State private var statusMessage: String?

    var body: some View {
        Section {
            Toggle("Enabled", isOn: Binding(
                get: { enabled },
                set: { value in
                    enabled = value && hasSavedKey
                    SubtitleProviderConfiguration.setEnabled(enabled, provider: provider)
                }
            ))
            .disabled(!hasSavedKey)

            SecureField(hasSavedKey ? "API key saved — enter a replacement" : "API key", text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()

            if provider == .openSubtitles {
                SecureField("User bearer token for downloads (optional)", text: $bearerToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Text("Search uses the API key. Downloads also require an OpenSubtitles user token.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(isTesting ? "Testing…" : "Test Connection & Save") {
                Task { await testAndSave() }
            }
            .disabled(isTesting)

            if hasSavedKey {
                Button("Remove Credentials", role: .destructive) { removeCredentials() }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(provider.displayName)
        }
        .onAppear {
            hasSavedKey = SubtitleProviderCredentialStore.value(keyAccount) != nil
            enabled = SubtitleProviderConfiguration.isEnabled(provider)
        }
    }

    private var keyAccount: String { "\(provider.rawValue).key" }

    private func testAndSave() async {
        let proposedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = proposedKey.isEmpty ? SubtitleProviderCredentialStore.value(keyAccount) : proposedKey
        guard let key, !key.isEmpty else {
            statusMessage = "Enter an API key first."
            return
        }
        let proposedBearer = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let bearer = proposedBearer.isEmpty
            ? SubtitleProviderCredentialStore.value("opensubtitles.bearer") : proposedBearer
        isTesting = true
        defer { isTesting = false }
        do {
            switch provider {
            case .openSubtitles:
                try await OpenSubtitlesRESTProvider(apiKey: key, bearerToken: bearer).testConnection()
            case .subDL:
                try await SubDLSubtitleProvider(apiKey: key).testConnection()
            case .jimaku:
                try await JimakuSubtitleProvider(apiKey: key).testConnection()
            }
            try SubtitleProviderCredentialStore.save(key, account: keyAccount)
            if provider == .openSubtitles, !proposedBearer.isEmpty {
                try SubtitleProviderCredentialStore.save(proposedBearer, account: "opensubtitles.bearer")
            }
            hasSavedKey = true
            enabled = true
            SubtitleProviderConfiguration.setEnabled(true, provider: provider)
            statusMessage = "Connection verified and saved."
            apiKey = ""
            bearerToken = ""
        } catch {
            if error is SubDLError || error is JimakuError || error is OpenSubtitlesRESTError {
                statusMessage = error.localizedDescription
            } else {
                statusMessage = "Connection failed. Check the key and network, then try again."
            }
        }
    }

    private func removeCredentials() {
        SubtitleProviderCredentialStore.delete(keyAccount)
        if provider == .openSubtitles { SubtitleProviderCredentialStore.delete("opensubtitles.bearer") }
        SubtitleProviderConfiguration.setEnabled(false, provider: provider)
        enabled = false
        hasSavedKey = false
        apiKey = ""
        bearerToken = ""
        statusMessage = "Credentials removed."
    }
}
