import CryptoKit
import CoreFoundation
import Foundation

struct SubtitleTranslationItem: Sendable, Equatable {
    let id: String
    let text: String
    let start: TimeInterval
}

struct SubtitleTranslationBatch: Sendable {
    let id: Int
    let items: [SubtitleTranslationItem]
    let contextBefore: [SubtitleTranslationItem]
    let contextAfter: [SubtitleTranslationItem]
    let glossary: [String]
    let preservesHonorifics: Bool
}

protocol TranslationProvider: Sendable {
    /// Returns the assistant's raw JSON content. Validation belongs to the orchestrator.
    func translate(_ batch: SubtitleTranslationBatch) async throws -> String
    func testConnection() async throws
}

enum SubtitleTranslationError: LocalizedError, Sendable {
    case invalidConfiguration, missingKey, connection, rateLimited, invalidResponse, server

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return String(localized: "API adresi veya model geçersiz.")
        case .missingKey: return String(localized: "API anahtarı eksik")
        case .connection: return String(localized: "API bağlantısı başarısız.")
        case .rateLimited: return String(localized: "İstek sınırı aşıldı.")
        case .invalidResponse: return String(localized: "Geçersiz API yanıtı.")
        case .server: return String(localized: "AI çeviri başarısız")
        }
    }
}

/// Supports POST {base}/chat/completions or an explicit .../chat/completions URL.
/// Contract: model + system/user messages; choices[0].message.content is JSON.
struct OpenAICompatibleTranslationProvider: TranslationProvider {
    let baseURL: String
    let apiKey: String
    let model: String
    var session: URLSession = .shared

    private var endpoint: URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let host = components.host, !host.isEmpty else { return nil }
        let local = host == "localhost" || host == "127.0.0.1"
        guard components.scheme?.lowercased() == "https" ||
              (local && components.scheme?.lowercased() == "http") else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") { components.path = "/" + path }
        else { components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/")) }
        return components.url
    }

    func translate(_ batch: SubtitleTranslationBatch) async throws -> String {
        let input: [String: Any] = [
            "items": batch.items.map { ["id": $0.id, "text": $0.text] },
            "context_before": batch.contextBefore.map { ["id": $0.id, "text": $0.text] },
            "context_after": batch.contextAfter.map { ["id": $0.id, "text": $0.text] },
            "glossary": batch.glossary
        ]
        let data = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let userContent = String(decoding: data, as: UTF8.self)
        let honorific = batch.preservesHonorifics
            ? "Preserve Japanese honorifics (-san, -kun, -chan, -sama, -senpai, -sensei)."
            : ""
        let system = """
        subtitle-tr-v1. Translate only items into natural concise Turkish subtitles. Preserve meaning, tone, humor, names and formality. Do not add explanations or omit meaning. Keep every protected private-use placeholder exactly once and in order; they encode formatting and line breaks. Context is read-only: never return translations for context IDs. \(honorific) Return only JSON: {"translations":[{"id":"source ID","text":"Turkish text"}]} with exactly one entry per item ID.
        """
        let inputCharacters = batch.items.reduce(0) { $0 + $1.text.count }
        let outputLimit = min(8_192, max(512, (inputCharacters + 1) / 2 + batch.items.count * 24))
        return try await send(messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent]
        ], maxTokens: outputLimit, timeout: 180)
    }

    func testConnection() async throws {
        let content = try await send(messages: [
            ["role": "system", "content": "Return only JSON. Do not translate anything."],
            ["role": "user", "content": "Return exactly {\"ok\":true} as JSON."]
        ], maxTokens: 32, timeout: 20, temperature: 0)
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count == 1, let value = object["ok"],
              CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(),
              value as? Bool == true else { throw SubtitleTranslationError.invalidResponse }
    }

    private func send(messages: [[String: String]], maxTokens: Int,
                      timeout: TimeInterval, temperature: Double? = nil) async throws -> String {
        guard let endpoint, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubtitleTranslationError.invalidConfiguration
        }
        guard !apiKey.isEmpty else { throw SubtitleTranslationError.missingKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["model": model, "messages": messages, "max_tokens": maxTokens]
        if let temperature { body["temperature"] = temperature }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SubtitleTranslationError.connection }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw SubtitleTranslationError.connection }
        switch http.statusCode {
        case 200..<300: break
        case 429: throw SubtitleTranslationError.rateLimited
        case 408, 500...599: throw SubtitleTranslationError.server
        default: throw SubtitleTranslationError.connection
        }
        guard data.count <= 2_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SubtitleTranslationError.invalidResponse
        }
        return content
    }
}

enum SubtitleTranslationResponse {
    static func validate(_ raw: String, expectedIDs: [String]) throws -> [String: String] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["translations"] as? [[String: Any]],
              entries.count == expectedIDs.count else { throw SubtitleTranslationError.invalidResponse }
        let expected = Set(expectedIDs)
        guard expected.count == expectedIDs.count else { throw SubtitleTranslationError.invalidResponse }
        var result: [String: String] = [:]
        for entry in entries {
            guard let id = entry["id"] as? String, expected.contains(id), result[id] == nil,
                  let text = entry["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SubtitleTranslationError.invalidResponse
            }
            result[id] = text
        }
        guard result.count == expected.count else { throw SubtitleTranslationError.invalidResponse }
        return result
    }
}

struct SubtitleTranslationConfiguration: Sendable {
    let baseURL: String
    let model: String
    let preservesHonorifics: Bool
    let glossary: [String]
}

enum SubtitleTranslationIdentity {
    static func sourceHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func cacheKey(source: Data, configuration: SubtitleTranslationConfiguration,
                         promptVersion: String = SubtitleTranslationSettings.promptVersion) -> String {
        let fields = [sourceHash(source), "tr", promptVersion,
                      configuration.baseURL.lowercased(), configuration.model,
                      configuration.preservesHonorifics ? "honorifics" : "no-honorifics",
                      configuration.glossary.joined(separator: "\u{1f}")]
        return sourceHash(Data(fields.joined(separator: "\u{0}").utf8))
    }
}

protocol TranslationCacheStore: Sendable {
    func load(_ key: String) async -> String?
    func save(_ text: String, for key: String) async
    func clear() async
}

actor DiskSubtitleTranslationCache: TranslationCacheStore {
    static let shared = DiskSubtitleTranslationCache()
    private let directory: URL
    private let maximumBytes: Int

    init(directory: URL? = nil, maximumBytes: Int = 64 * 1_024 * 1_024) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? support.appendingPathComponent("SubtitleAITranslations", isDirectory: true)
        self.maximumBytes = maximumBytes
    }

    func load(_ key: String) async -> String? {
        guard isKey(key), let data = try? Data(contentsOf: path(key)),
              data.count <= SubtitleFileHandling.maximumBytes,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path(key).path)
        return text
    }

    func save(_ text: String, for key: String) async {
        guard isKey(key), !text.isEmpty,
              let data = text.data(using: .utf8), data.count <= min(maximumBytes, SubtitleFileHandling.maximumBytes) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: path(key), options: .atomic)
        evictIfNeeded()
    }

    func clear() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "subtitle" { try? FileManager.default.removeItem(at: file) }
    }

    private func path(_ key: String) -> URL { directory.appendingPathComponent(key).appendingPathExtension("subtitle") }
    private func isKey(_ key: String) -> Bool { key.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil }

    private func evictIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let entries = files.filter { $0.pathExtension == "subtitle" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where total > maximumBytes {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}

enum SubtitleAITemporaryFiles {
    static func cleanupStale(directory: URL = FileManager.default.temporaryDirectory,
                             olderThan age: TimeInterval = 24 * 60 * 60, now: Date = Date()) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return }
        for file in files where file.lastPathComponent.hasPrefix("subtitle-ai-") {
            guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) > age else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func cleanup(_ urls: [URL], directory: URL = FileManager.default.temporaryDirectory) {
        let root = directory.standardizedFileURL
        for url in urls {
            let file = url.standardizedFileURL
            guard file.deletingLastPathComponent() == root,
                  file.lastPathComponent.hasPrefix("subtitle-ai-") else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}

enum SubtitleTranslationSourcePolicy {
    static func selectedEnglish(language: String?, format: String?, isMachineTranslated: Bool) -> Bool {
        guard StremioSubtitleLanguagePolicy.canonicalCode(language) == "en",
              !isMachineTranslated else { return false }
        guard let format, !format.isEmpty else { return true } // Inspect the downloaded bytes before translation.
        return ["srt", "vtt", "ass", "ssa", "zip", "gz"].contains(format.lowercased())
    }

    static func embeddedEnglishText(name: String, codec: String,
                                    hasCompleteTimedText: Bool) -> Bool {
        guard hasCompleteTimedText,
              StremioSubtitleLanguagePolicy.canonicalCode(name) == "en" else { return false }
        let value = codec.lowercased()
        return ["subrip", "ass", "ssa", "webvtt", "mov_text", "text", "tx3g"]
            .contains { value.contains($0) }
    }

    static func shouldStart(mode: SubtitleTranslationMode, hasHumanTurkish: Bool,
                            hasGoodHumanEnglish: Bool, userConfirmed: Bool) -> Bool {
        guard hasGoodHumanEnglish else { return false }
        switch mode {
        case .off: return false
        case .ask: return userConfirmed
        case .automatic: return !hasHumanTurkish
        }
    }

    static func bestEnglish(_ candidates: [SubtitleCandidate]) -> SubtitleCandidate? {
        candidates.filter {
            ["en", "eng", "en-us", "english"].contains($0.language.lowercased())
                && !$0.isMachineTranslated
                && SubtitleRanking.accepts($0) && $0.score >= 80
                && hasEpisodeEvidence($0)
        }.sorted { $0.score > $1.score }.first
    }

    static func hasGoodTurkish(_ candidates: [SubtitleCandidate]) -> Bool {
        candidates.contains {
            ["tr", "tur", "tr-tr", "turkish"].contains($0.language.lowercased())
                && !$0.isMachineTranslated && SubtitleRanking.accepts($0)
                && $0.score >= 70 && hasEpisodeEvidence($0)
        }
    }

    private static func hasEpisodeEvidence(_ candidate: SubtitleCandidate) -> Bool {
        candidate.matchReasons.contains {
            $0 == "Video hash eşleşti" ||
            ($0.hasPrefix("Absolute episode ") && $0.hasSuffix(" eşleşti")) ||
            ($0.hasPrefix("S") && $0.contains("E") && $0.hasSuffix(" eşleşti"))
        }
    }
}

struct ExplicitAISourceSelection {
    private(set) var generation = 0
    private(set) var selectedURL: String?

    mutating func beginMedia(generation: Int) {
        self.generation = generation
        selectedURL = nil
    }

    mutating func select(url: String, generation: Int) {
        guard generation == self.generation else { return }
        selectedURL = url
    }

    func isCurrent(url: String, generation: Int, isActiveTrack: Bool) -> Bool {
        isActiveTrack && generation == self.generation && selectedURL == url
    }
}

enum SubtitleTranslationPlaybackGuard {
    static func mayAutoSwap(expectedGeneration: Int, currentGeneration: Int,
                            expectedManualRevision: Int, currentManualRevision: Int,
                            selection: SubtitlePlaybackSelection, isClosing: Bool) -> Bool {
        !isClosing && expectedGeneration == currentGeneration &&
            expectedManualRevision == currentManualRevision && selection.choice != .user
    }
}

enum SubtitleTranslationBatching {
    static func make(_ units: [SubtitleTranslationUnit], glossary: [String],
                     preservesHonorifics: Bool) -> [SubtitleTranslationBatch] {
        let items = units.map { SubtitleTranslationItem(id: $0.id, text: $0.translationTemplate, start: $0.start) }
        var groups: [Range<Int>] = []
        var lower = 0
        while lower < items.count {
            var upper = lower
            var characters = 0
            while upper < items.count && upper - lower < 50 &&
                    (upper == lower || characters + items[upper].text.count <= 12_000) {
                characters += items[upper].text.count
                upper += 1
            }
            groups.append(lower..<upper)
            lower = upper
        }
        return groups.enumerated().map { id, range in
            SubtitleTranslationBatch(id: id, items: Array(items[range]),
                contextBefore: Array(items[max(0, range.lowerBound - 5)..<range.lowerBound]).map {
                    SubtitleTranslationItem(id: $0.id, text: String($0.text.prefix(300)), start: $0.start)
                },
                contextAfter: Array(items[range.upperBound..<min(items.count, range.upperBound + 5)]).map {
                    SubtitleTranslationItem(id: $0.id, text: String($0.text.prefix(300)), start: $0.start)
                },
                glossary: Array(glossary.prefix(24)), preservesHonorifics: preservesHonorifics)
        }
    }

    static func priority(_ batches: [SubtitleTranslationBatch], playbackTime: TimeInterval) -> [Int] {
        let chronological = batches.sorted { ($0.items.first?.start ?? 0) < ($1.items.first?.start ?? 0) }
        guard let current = chronological.lastIndex(where: { ($0.items.first?.start ?? 0) <= playbackTime }) else {
            return chronological.map(\.id)
        }
        let currentBatch = [chronological[current].id]
        let upcoming = chronological.dropFirst(current + 1).map(\.id)
        let past = chronological.prefix(current).reversed().map(\.id)
        return currentBatch + upcoming + past
    }
}

private actor SubtitleTranslationQueue {
    private var pending: [SubtitleTranslationBatch]
    private var playbackTime: TimeInterval

    init(_ batches: [SubtitleTranslationBatch], playbackTime: TimeInterval) {
        pending = batches
        self.playbackTime = playbackTime
    }

    func updatePosition(_ time: TimeInterval) { playbackTime = max(0, time) }

    func next() -> SubtitleTranslationBatch? {
        guard let id = SubtitleTranslationBatching.priority(pending, playbackTime: playbackTime).first,
              let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
        return pending.remove(at: index)
    }
}

struct SubtitleTranslationSnapshot {
    let text: String
    let translated: Int
    let total: Int
    let isComplete: Bool
    let fromCache: Bool
}

actor SubtitleTranslationEngine {
    private let provider: any TranslationProvider
    private let cache: any TranslationCacheStore
    private var queue: SubtitleTranslationQueue?

    init(provider: any TranslationProvider, cache: any TranslationCacheStore = DiskSubtitleTranslationCache.shared) {
        self.provider = provider
        self.cache = cache
    }

    func updatePlaybackPosition(_ time: TimeInterval) async { await queue?.updatePosition(time) }

    func translate(source: Data, format: SubtitleDocumentFormat,
                   configuration: SubtitleTranslationConfiguration, playbackTime: TimeInterval,
                   onProgress: @escaping @MainActor (SubtitleTranslationSnapshot) -> Void) async throws -> SubtitleTranslationSnapshot {
        try Task.checkCancellation()
        var document = try SubtitleDocument.parse(source, format: format)
        let units = document.translatableUnits
        let key = SubtitleTranslationIdentity.cacheKey(source: source, configuration: configuration)
        if let cached = await cache.load(key),
           let cachedDocument = try? SubtitleDocument.parse(cached, format: format),
           !units.isEmpty, cachedDocument.translatableUnits.count == units.count {
            let snapshot = SubtitleTranslationSnapshot(text: cached, translated: units.count, total: units.count,
                                                       isComplete: true, fromCache: true)
            try Task.checkCancellation()
            await onProgress(snapshot)
            return snapshot
        }
        guard !units.isEmpty else {
            return SubtitleTranslationSnapshot(text: try document.serialize(), translated: 0,
                                               total: 0, isComplete: true, fromCache: false)
        }
        let batches = SubtitleTranslationBatching.make(units, glossary: configuration.glossary,
            preservesHonorifics: configuration.preservesHonorifics)
        let workQueue = SubtitleTranslationQueue(batches, playbackTime: playbackTime)
        queue = workQueue
        defer { queue = nil }
        let provider = self.provider
        var translated = 0
        await withTaskGroup(of: [String: String].self) { group in
            for _ in 0..<min(2, batches.count) {
                if let batch = await workQueue.next() {
                    group.addTask { await Self.translateWithFallback(batch, provider: provider) }
                }
            }
            while let result = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                for (id, text) in result {
                    if (try? document.applyTranslation(id: id, text: text)) != nil { translated += 1 }
                }
                if let text = try? document.serialize() {
                    let snapshot = SubtitleTranslationSnapshot(text: text, translated: translated,
                        total: units.count, isComplete: false, fromCache: false)
                    await onProgress(snapshot)
                }
                if let batch = await workQueue.next() {
                    group.addTask { await Self.translateWithFallback(batch, provider: provider) }
                }
            }
        }
        try Task.checkCancellation()
        let text = try document.serialize()
        let snapshot = SubtitleTranslationSnapshot(text: text, translated: translated,
            total: units.count, isComplete: true, fromCache: false)
        if translated == units.count { await cache.save(text, for: key) }
        await onProgress(snapshot)
        return snapshot
    }

    private static func translateWithFallback(_ batch: SubtitleTranslationBatch,
                                              provider: any TranslationProvider) async -> [String: String] {
        do {
            for attempt in 0..<2 {
                try Task.checkCancellation()
                do {
                    let response = try await provider.translate(batch)
                    let translations = try SubtitleTranslationResponse.validate(response,
                        expectedIDs: batch.items.map(\.id))
                    guard batch.items.allSatisfy({ item in
                        guard let translated = translations[item.id] else { return false }
                        return protectedMarkers(in: item.text) == protectedMarkers(in: translated)
                    }) else { throw SubtitleTranslationError.invalidResponse }
                    return translations
                } catch is CancellationError { return [:] }
                catch {
                    if attempt == 0 {
                        let delay = UInt64(200_000_000 + Int.random(in: 0...100_000_000))
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
            }
            if batch.items.count > 1 {
                let middle = batch.items.count / 2
                var first = batch
                first = SubtitleTranslationBatch(id: batch.id, items: Array(batch.items[..<middle]),
                    contextBefore: batch.contextBefore, contextAfter: batch.contextAfter,
                    glossary: batch.glossary, preservesHonorifics: batch.preservesHonorifics)
                let second = SubtitleTranslationBatch(id: batch.id, items: Array(batch.items[middle...]),
                    contextBefore: batch.contextBefore, contextAfter: batch.contextAfter,
                    glossary: batch.glossary, preservesHonorifics: batch.preservesHonorifics)
                let left = await translateWithFallback(first, provider: provider)
                let right = await translateWithFallback(second, provider: provider)
                return left.merging(right) { _, new in new }
            }
        } catch { return [:] }
        return [:]
    }

    private static func protectedMarkers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\u{E000}[^\u{E001}]*\u{E001}") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
