import Foundation
import Security

enum DirectSubtitleProviderKind: String, CaseIterable {
    case openSubtitles = "opensubtitles-rest"
    case subDL = "subdl"
    case jimaku = "jimaku"

    var displayName: String {
        switch self {
        case .openSubtitles: return "OpenSubtitles.com"
        case .subDL: return "SubDL"
        case .jimaku: return "Jimaku"
        }
    }
}

enum SubtitleProviderConfiguration {
    static func isEnabled(_ provider: DirectSubtitleProviderKind, defaults: UserDefaults = ProfileSettingsStore.active) -> Bool {
        defaults.bool(forKey: "subtitleProvider.\(provider.rawValue).enabled")
    }

    static func setEnabled(_ enabled: Bool, provider: DirectSubtitleProviderKind,
                           defaults: UserDefaults = ProfileSettingsStore.active) {
        defaults.set(enabled, forKey: "subtitleProvider.\(provider.rawValue).enabled")
    }

    static func activeProviders() -> [any SubtitleProvider] {
        var providers: [any SubtitleProvider] = []
        if isEnabled(.openSubtitles), let key = SubtitleProviderCredentialStore.value("opensubtitles-rest.key") {
            providers.append(OpenSubtitlesRESTProvider(
                apiKey: key,
                bearerToken: SubtitleProviderCredentialStore.value("opensubtitles.bearer")
            ))
        }
        if isEnabled(.subDL), let key = SubtitleProviderCredentialStore.value("subdl.key") {
            providers.append(SubDLSubtitleProvider(apiKey: key))
        }
        if isEnabled(.jimaku), let key = SubtitleProviderCredentialStore.value("jimaku.key") {
            providers.append(JimakuSubtitleProvider(apiKey: key))
        }
        return providers
    }

    @MainActor
    static func searchActive(
        _ query: SubtitleQuery,
        videoURL: URL? = nil,
        onBatch: (@MainActor ([SubtitleProviderSearchResult]) -> Void)? = nil
    ) async -> [SubtitleProviderSearchResult] {
        let providers = activeProviders()
        guard !providers.isEmpty else { return [] }
        var effectiveQuery = query
        let hasOpenSubtitlesHash = effectiveQuery.videoHash?.range(
            of: #"^[a-fA-F0-9]{16}$"#, options: .regularExpression
        ) != nil
        if !hasOpenSubtitlesHash,
           let videoURL, let size = effectiveQuery.fileSize {
            effectiveQuery.videoHash = await SubtitleMovieHash.fromHTTP(url: videoURL, fileSize: size)
        }
        return await SubtitleProviderSearchCoordinator.search(
            query: effectiveQuery, providers: providers, onBatch: onBatch
        )
    }
}

enum SubtitleProviderCredentialStore {
    private static let service = "app.Eclipse.Soupy.subtitle-providers"

    static func value(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    static func save(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CredentialError.empty }
        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw CredentialError.storageFailed }
        var insert = query
        insert.merge(attributes) { _, new in new }
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw CredentialError.storageFailed
        }
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    enum CredentialError: LocalizedError {
        case empty, storageFailed

        var errorDescription: String? {
            switch self {
            case .empty: return "Enter an API key."
            case .storageFailed: return "Could not save the credential in Keychain."
            }
        }
    }
}

enum SubtitleTranslationMode: String, CaseIterable {
    case off, ask, automatic

    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .ask: return "Sor"
        case .automatic: return "Otomatik"
        }
    }
}

enum SubtitleTranslationSettings {
    static let keyAccount = "ai-translation.key"
    static let promptVersion = "subtitle-tr-v1"

    static var mode: SubtitleTranslationMode {
        get { SubtitleTranslationMode(rawValue: ProfileSettingsStore.active.string(forKey: "subtitleAI.mode") ?? "off") ?? .off }
        set { ProfileSettingsStore.active.set(newValue.rawValue, forKey: "subtitleAI.mode") }
    }

    static var baseURL: String {
        get { ProfileSettingsStore.active.string(forKey: "subtitleAI.baseURL") ?? "https://api.openai.com/v1" }
        set { ProfileSettingsStore.active.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "subtitleAI.baseURL") }
    }

    static var model: String {
        get { ProfileSettingsStore.active.string(forKey: "subtitleAI.model") ?? "" }
        set { ProfileSettingsStore.active.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "subtitleAI.model") }
    }

    static var preservesHonorifics: Bool {
        get { ProfileSettingsStore.active.object(forKey: "subtitleAI.honorifics") as? Bool ?? true }
        set { ProfileSettingsStore.active.set(newValue, forKey: "subtitleAI.honorifics") }
    }

    static var hasKey: Bool { SubtitleProviderCredentialStore.value(keyAccount) != nil }
}
