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

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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

/// Removes only data owned by the retired subtitle feature. Provider credentials stay intact.
enum RetiredSubtitleDataCleanup {
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        let marker = "retiredSubtitleDataRemovedV1"
        guard !defaults.bool(forKey: marker) else { return }
        // Keep the exact old account solely so existing installations can discard it.
        guard SubtitleProviderCredentialStore.delete("ai-translation.key") else { return }
        let files = FileManager.default
        do {
            if let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let cache = support.appendingPathComponent("SubtitleAITranslations", isDirectory: true)
                // removeItem removes a symlink itself, without traversing its destination.
                if files.fileExists(atPath: cache.path) || (try? files.destinationOfSymbolicLink(atPath: cache.path)) != nil {
                    try files.removeItem(at: cache)
                }
            }
            for file in try files.contentsOfDirectory(at: files.temporaryDirectory,
                                                      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                where file.lastPathComponent.hasPrefix("subtitle-ai-") {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
                try files.removeItem(at: file)
            }
            defaults.set(true, forKey: marker)
        } catch {
            // Retry on a later launch; avoid logging paths or credential information.
            Logger.shared.log("Retired subtitle data cleanup deferred", type: "Player")
        }
    }
}
