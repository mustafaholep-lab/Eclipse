import Foundation
import XCTest
@testable import Eclipse

private final class TranslationHTTPFixture: URLProtocol {
    static var statusCode = 200
    static var failure: Error?
    static var seenRequest: URLRequest?
    static var content = #"{"ok":true}"#

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seenRequest = request
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let body = try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": Self.content]]]
        ])
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor MockTranslationProvider: TranslationProvider {
    enum Reply: Sendable { case automatic, raw(String), failure(SubtitleTranslationError) }
    private var replies: [Reply]
    private let delay: UInt64
    private(set) var calls = 0
    private(set) var maxActive = 0
    private var active = 0
    private(set) var batches: [SubtitleTranslationBatch] = []

    init(_ replies: [Reply] = [], delay: UInt64 = 0) {
        self.replies = replies
        self.delay = delay
    }

    func translate(_ batch: SubtitleTranslationBatch) async throws -> String {
        calls += 1
        batches.append(batch)
        active += 1
        maxActive = max(maxActive, active)
        defer { active -= 1 }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let reply = replies.isEmpty ? .automatic : replies.removeFirst()
        switch reply {
        case .automatic:
            let entries = batch.items.map { item in
                ["id": item.id, "text": item.text.contains("Hello")
                    ? item.text.replacingOccurrences(of: "Hello", with: "Merhaba")
                    : "TR:" + item.text]
            }
            let data = try JSONSerialization.data(withJSONObject: ["translations": entries])
            return String(decoding: data, as: UTF8.self)
        case .raw(let raw): return raw
        case .failure(let error): throw error
        }
    }

    func testConnection() async throws {}
}

private actor MockTranslationCache: TranslationCacheStore {
    private var values: [String: String] = [:]
    func load(_ key: String) async -> String? { values[key] }
    func save(_ text: String, for key: String) async { values[key] = text }
    func clear() async { values.removeAll() }
    func corrupt(_ key: String) { values[key] = "garbage" }
}

final class SubtitleTranslationTests: XCTestCase {
    private let invalid = "{\"translations\":[{\"id\":\"wrong\",\"text\":\"no\"}]}"

    private func config(_ model: String = "test-model") -> SubtitleTranslationConfiguration {
        .init(baseURL: "https://api.example/v1", model: model,
              preservesHonorifics: true, glossary: ["Jujutsu Kaisen", "Gojo"])
    }

    private func source(_ count: Int = 2) -> Data {
        Data((0..<count).map { index in
            let start = String(format: "%02d:%02d:%02d", index / 3600, (index / 60) % 60, index % 60)
            let end = String(format: "%02d:%02d:%02d", (index + 1) / 3600, ((index + 1) / 60) % 60, (index + 1) % 60)
            return "\(index + 1)\n\(start),000 --> \(end),000\nLine \(index)\n"
        }.joined(separator: "\n").utf8)
    }

    func testHTTPStatusAndChatCompletionsContractWithoutLiveAPI() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationHTTPFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let provider = OpenAICompatibleTranslationProvider(baseURL: "https://api.example/v1",
            apiKey: "fixture-key", model: "fixture-model", session: session)
        TranslationHTTPFixture.statusCode = 200
        TranslationHTTPFixture.failure = nil
        TranslationHTTPFixture.content = #"{"ok":true}"#
        try await provider.testConnection()
        XCTAssertEqual(TranslationHTTPFixture.seenRequest?.url?.path, "/v1/chat/completions")
        XCTAssertEqual(TranslationHTTPFixture.seenRequest?.httpMethod, "POST")
        XCTAssertEqual(TranslationHTTPFixture.seenRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let testBody = try XCTUnwrap(TranslationHTTPFixture.seenRequest?.httpBody)
        let testJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: testBody) as? [String: Any])
        XCTAssertEqual(testJSON["max_tokens"] as? Int, 32)
        XCTAssertEqual(testJSON["temperature"] as? Double, 0)
        XCTAssertEqual(TranslationHTTPFixture.seenRequest?.timeoutInterval, 20)
        TranslationHTTPFixture.content = #"{"ok":1}"#
        do { try await provider.testConnection(); XCTFail("Strict JSON validation must reject numeric ok") }
        catch let error as SubtitleTranslationError {
            guard case .invalidResponse = error else { return XCTFail("Wrong validation error") }
        }
        TranslationHTTPFixture.content = #"{"ok":true,"extra":1}"#
        do { try await provider.testConnection(); XCTFail("Strict JSON validation must reject extra fields") }
        catch let error as SubtitleTranslationError {
            guard case .invalidResponse = error else { return XCTFail("Wrong validation error") }
        }
        TranslationHTTPFixture.content = #"{"ok":true}"#
        for status in [429, 408, 500, 502, 503] {
            TranslationHTTPFixture.statusCode = status
            do { try await provider.testConnection(); XCTFail("Expected HTTP \(status) failure") }
            catch let error as SubtitleTranslationError {
                switch (status, error) {
                case (429, .rateLimited), (408, .server), (500, .server),
                     (502, .server), (503, .server): break
                default: XCTFail("Wrong error for HTTP \(status)")
                }
            }
        }
        TranslationHTTPFixture.failure = URLError(.timedOut)
        defer { TranslationHTTPFixture.failure = nil }
        do { try await provider.testConnection(); XCTFail("Expected timeout") }
        catch let error as SubtitleTranslationError {
            guard case .connection = error else { return XCTFail("Wrong timeout error") }
        }
    }

    func testResponseValidationAcceptsReorderedIDs() throws {
        let response = "{\"translations\":[{\"id\":\"b\",\"text\":\"İki\"},{\"id\":\"a\",\"text\":\"Bir\"}]}"
        XCTAssertEqual(try SubtitleTranslationResponse.validate(response, expectedIDs: ["a", "b"]),
                       ["a": "Bir", "b": "İki"])
    }

    func testResponseValidationRejectsMalformedMissingExtraDuplicateAndEmpty() {
        let bad = [
            "not JSON",
            "{\"translations\":[{\"id\":\"a\",\"text\":\"Bir\"}]}",
            "{\"translations\":[{\"id\":\"a\",\"text\":\"Bir\"},{\"id\":\"extra\",\"text\":\"X\"}]}",
            "{\"translations\":[{\"id\":\"a\",\"text\":\"Bir\"},{\"id\":\"a\",\"text\":\"İki\"}]}",
            "{\"translations\":[{\"id\":\"a\",\"text\":\"Bir\"},{\"id\":\"b\",\"text\":\"  \"}]}"
        ]
        for response in bad {
            XCTAssertThrowsError(try SubtitleTranslationResponse.validate(response, expectedIDs: ["a", "b"]))
        }
    }

    func testRetryThenValidAndCacheHitAvoidsProvider() async throws {
        let provider = MockTranslationProvider([.raw(invalid), .automatic])
        let cache = MockTranslationCache()
        let engine = SubtitleTranslationEngine(provider: provider, cache: cache)
        let input = source()
        let first = try await engine.translate(source: input, format: .srt, configuration: config(),
                                               playbackTime: 0) { _ in }
        XCTAssertEqual(first.translated, 2)
        XCTAssertTrue(first.text.contains("TR:Line 0"))
        let second = try await engine.translate(source: input, format: .srt, configuration: config(),
                                                playbackTime: 0) { _ in }
        XCTAssertTrue(second.fromCache)
        XCTAssertEqual(second.translated, 2)
        XCTAssertEqual(second.total, 2)
        let calls = await provider.calls
        XCTAssertEqual(calls, 2)
    }

    func testSmallerBatchRetryAndFinalSourceFallback() async throws {
        let provider = MockTranslationProvider([.raw(invalid), .raw(invalid), .automatic, .automatic])
        let engine = SubtitleTranslationEngine(provider: provider, cache: MockTranslationCache())
        let result = try await engine.translate(source: source(4), format: .srt,
                                                configuration: config(), playbackTime: 0) { _ in }
        XCTAssertEqual(result.translated, 4)
        let calls = await provider.calls
        XCTAssertEqual(calls, 4)

        let failure = MockTranslationProvider(Array(repeating: .raw(invalid), count: 8))
        let failedEngine = SubtitleTranslationEngine(provider: failure, cache: MockTranslationCache())
        let original = source(1)
        let fallback = try await failedEngine.translate(source: original, format: .srt,
            configuration: config(), playbackTime: 0) { _ in }
        XCTAssertEqual(fallback.translated, 0)
        XCTAssertEqual(fallback.text, String(decoding: original, as: UTF8.self))
    }

    func testTransientErrorsAndCancellation() async throws {
        for error in [SubtitleTranslationError.rateLimited, .server, .connection] {
            let provider = MockTranslationProvider([.failure(error), .automatic])
            let result = try await SubtitleTranslationEngine(provider: provider,
                cache: MockTranslationCache()).translate(source: source(1), format: .srt,
                    configuration: config(), playbackTime: 0) { _ in }
            XCTAssertEqual(result.translated, 1)
            let calls = await provider.calls
            XCTAssertEqual(calls, 2)
        }
        let slow = MockTranslationProvider(delay: 1_000_000_000)
        let task = Task {
            try await SubtitleTranslationEngine(provider: slow, cache: MockTranslationCache())
                .translate(source: source(1), format: .srt, configuration: config(), playbackTime: 0) { _ in }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled translation must not publish") }
        catch is CancellationError { }
    }

    func testConcurrencyCapAndPlaybackOrdering() async throws {
        let provider = MockTranslationProvider(delay: 20_000_000)
        let engine = SubtitleTranslationEngine(provider: provider, cache: MockTranslationCache())
        let result = try await engine.translate(source: source(120), format: .srt,
                                                configuration: config(), playbackTime: 65) { _ in }
        XCTAssertEqual(result.translated, 120)
        let maxActive = await provider.maxActive
        XCTAssertLessThanOrEqual(maxActive, 2)
        let batches = await provider.batches
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(Set(batches.flatMap { $0.items.map(\.id) }).count, 120)
        XCTAssertTrue(batches.allSatisfy { $0.items.count <= 50 })
        XCTAssertTrue(batches.allSatisfy { batch in
            Set(batch.items.map(\.id)).isDisjoint(with: Set(batch.contextBefore.map(\.id) + batch.contextAfter.map(\.id)))
        })
        let fixture = (0..<120).map { index in
            SubtitleTranslationUnit(id: "srt:\(index)", start: Double(index), end: Double(index + 1),
                originalText: "x", plainText: "x", translationTemplate: "x",
                format: .srt, skipReason: nil, duplicateOf: nil)
        }
        let ordered = SubtitleTranslationBatching.make(fixture, glossary: [], preservesHonorifics: true)
        XCTAssertEqual(SubtitleTranslationBatching.priority(ordered, playbackTime: 65), [1, 2, 0])
    }

    func testASSIntegrationSkipsNonDialogueAndRestoresLayersTagsBreaks() async throws {
        let ass = """
        [Script Info]
        Title: fixture
        [Events]
        Format: Layer, Start, End, Style, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,{\\i1}Hello{\\i0}\\NGojo-san
        Dialogue: 1,0:00:01.00,0:00:03.00,Default,{\\i1}Hello{\\i0}\\NGojo-san
        Dialogue: 0,0:00:04.00,0:00:05.00,Signs,{\\pos(100,200)}Exit
        Dialogue: 0,0:00:05.00,0:00:06.00,OP,{\\kf20}la
        """
        let provider = MockTranslationProvider()
        let result = try await SubtitleTranslationEngine(provider: provider, cache: MockTranslationCache())
            .translate(source: Data(ass.utf8), format: .ass, configuration: config(), playbackTime: 0) { _ in }
        let batches = await provider.batches
        XCTAssertEqual(batches.flatMap(\.items).count, 1)
        XCTAssertEqual(result.translated, 1)
        XCTAssertEqual(result.text.components(separatedBy: "{\\i1}Merhaba{\\i0}\\NGojo-san").count - 1, 2)
        XCTAssertTrue(result.text.contains("Signs,{\\pos(100,200)}Exit"))
        XCTAssertTrue(result.text.contains("OP,{\\kf20}la"))
    }

    func testDamagedProtectedMarkersRetryWithoutLosingASSFormatting() async throws {
        let ass = """
        [Events]
        Format: Layer, Start, End, Style, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,{\\i1}Hello{\\i0}\\NGojo
        """
        let provider = MockTranslationProvider([.raw("{\"translations\":[{\"id\":\"ass:0\",\"text\":\"Merhaba\"}]}"), .automatic])
        let result = try await SubtitleTranslationEngine(provider: provider, cache: MockTranslationCache())
            .translate(source: Data(ass.utf8), format: .ass, configuration: config(), playbackTime: 0) { _ in }
        XCTAssertEqual(result.translated, 1)
        XCTAssertTrue(result.text.contains("{\\i1}Merhaba{\\i0}\\NGojo"))
        let calls = await provider.calls
        XCTAssertEqual(calls, 2)
    }

    func testCacheIdentityCorruptionAndEviction() async throws {
        let input = source(1)
        let first = SubtitleTranslationIdentity.cacheKey(source: input, configuration: config())
        XCTAssertNotEqual(first, SubtitleTranslationIdentity.cacheKey(source: input, configuration: config("new-model")))
        XCTAssertNotEqual(first, SubtitleTranslationIdentity.cacheKey(source: input,
            configuration: config(), promptVersion: "subtitle-tr-v2"))
        XCTAssertEqual(first.count, 64)
        let provider = MockTranslationProvider()
        let cache = MockTranslationCache()
        await cache.corrupt(first)
        _ = try await SubtitleTranslationEngine(provider: provider, cache: cache)
            .translate(source: input, format: .srt, configuration: config(), playbackTime: 0) { _ in }
        let calls = await provider.calls
        XCTAssertEqual(calls, 1)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ai-cache-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = DiskSubtitleTranslationCache(directory: folder, maximumBytes: 30)
        let keyA = SubtitleTranslationIdentity.sourceHash(Data("A".utf8))
        let keyB = SubtitleTranslationIdentity.sourceHash(Data("B".utf8))
        await disk.save(String(repeating: "A", count: 20), for: keyA)
        try await Task.sleep(nanoseconds: 20_000_000)
        await disk.save(String(repeating: "B", count: 20), for: keyB)
        let firstEntry = await disk.load(keyA)
        let secondEntry = await disk.load(keyB)
        XCTAssertNil(firstEntry)
        XCTAssertNotNil(secondEntry)
        await disk.clear()
        let afterClear = await disk.load(keyB)
        XCTAssertNil(afterClear)
    }

    func testTranslationRequestUsesBoundedBatchSizedOutputBudget() async throws {
        TranslationHTTPFixture.statusCode = 200
        TranslationHTTPFixture.failure = nil
        TranslationHTTPFixture.content = #"{"translations":[]}"#
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationHTTPFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let provider = OpenAICompatibleTranslationProvider(baseURL: "https://api.example/v1",
            apiKey: "fixture-key", model: "fixture-model", session: session)
        let short = SubtitleTranslationBatch(id: 0,
            items: [.init(id: "1", text: "Hello", start: 0)],
            contextBefore: [], contextAfter: [], glossary: [], preservesHonorifics: true)
        let long = SubtitleTranslationBatch(id: 1,
            items: (0..<50).map { .init(id: String($0), text: String(repeating: "Hello ", count: 40), start: Double($0)) },
            contextBefore: [], contextAfter: [], glossary: [], preservesHonorifics: true)
        _ = try await provider.translate(short)
        let shortJSON = try XCTUnwrap(JSONSerialization.jsonObject(with:
            XCTUnwrap(TranslationHTTPFixture.seenRequest?.httpBody)) as? [String: Any])
        let shortLimit = try XCTUnwrap(shortJSON["max_tokens"] as? Int)
        XCTAssertGreaterThan(shortLimit, 32)
        XCTAssertLessThanOrEqual(shortLimit, 8_192)
        XCTAssertNil(shortJSON["temperature"])
        XCTAssertEqual(TranslationHTTPFixture.seenRequest?.timeoutInterval, 180)
        _ = try await provider.translate(long)
        let longJSON = try XCTUnwrap(JSONSerialization.jsonObject(with:
            XCTUnwrap(TranslationHTTPFixture.seenRequest?.httpBody)) as? [String: Any])
        let longLimit = try XCTUnwrap(longJSON["max_tokens"] as? Int)
        XCTAssertGreaterThan(longLimit, shortLimit)
        XCTAssertLessThanOrEqual(longLimit, 8_192)
    }

    func testAITemporaryCleanupOnlyRemovesManagedFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("subtitle-ai-source-test.srt")
        let translated = folder.appendingPathComponent("subtitle-ai-test.srt")
        let unrelated = folder.appendingPathComponent("other.srt")
        for file in [source, translated, unrelated] { try Data("cue".utf8).write(to: file) }
        SubtitleAITemporaryFiles.cleanup([source, translated, unrelated], directory: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: translated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testStaleAITemporaryCleanupPreservesRecentAndUnrelatedFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stale-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = folder.appendingPathComponent("subtitle-ai-old.srt")
        let recent = folder.appendingPathComponent("subtitle-ai-new.srt")
        let unrelated = folder.appendingPathComponent("other.srt")
        for file in [old, recent, unrelated] { try Data("cue".utf8).write(to: file) }
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100_000)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100_000)], ofItemAtPath: unrelated.path)
        SubtitleAITemporaryFiles.cleanupStale(directory: folder, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testModeAndManualSelectionSafety() {
        XCTAssertFalse(SubtitleTranslationSourcePolicy.shouldStart(mode: .off,
            hasHumanTurkish: false, hasGoodHumanEnglish: true, userConfirmed: true))
        XCTAssertFalse(SubtitleTranslationSourcePolicy.shouldStart(mode: .ask,
            hasHumanTurkish: false, hasGoodHumanEnglish: true, userConfirmed: false))
        XCTAssertTrue(SubtitleTranslationSourcePolicy.shouldStart(mode: .ask,
            hasHumanTurkish: false, hasGoodHumanEnglish: true, userConfirmed: true))
        XCTAssertFalse(SubtitleTranslationSourcePolicy.shouldStart(mode: .automatic,
            hasHumanTurkish: true, hasGoodHumanEnglish: true, userConfirmed: false))
        XCTAssertTrue(SubtitleTranslationSourcePolicy.shouldStart(mode: .automatic,
            hasHumanTurkish: false, hasGoodHumanEnglish: true, userConfirmed: false))
        var selection = SubtitlePlaybackSelection()
        selection.beginMedia()
        let generation = selection.generation
        XCTAssertTrue(SubtitleTranslationPlaybackGuard.mayAutoSwap(expectedGeneration: generation,
            currentGeneration: generation, expectedManualRevision: 0, currentManualRevision: 0,
            selection: selection, isClosing: false))
        selection.selectByUser()
        XCTAssertFalse(SubtitleTranslationPlaybackGuard.mayAutoSwap(expectedGeneration: generation,
            currentGeneration: generation, expectedManualRevision: 0, currentManualRevision: 1,
            selection: selection, isClosing: false))
        selection.beginMedia()
        XCTAssertFalse(SubtitleTranslationPlaybackGuard.mayAutoSwap(expectedGeneration: generation,
            currentGeneration: selection.generation, expectedManualRevision: 0, currentManualRevision: 0,
            selection: selection, isClosing: false))
    }

    func testEnglishSourceRequiresHumanAndEpisodeOrHashEvidence() {
        func candidate(_ score: Int, reasons: [String], machine: Bool = false,
                       language: String = "en") -> SubtitleCandidate {
            SubtitleCandidate(id: UUID().uuidString, providerID: "fixture", language: language,
                releaseName: "Jujutsu Kaisen S01E01", format: "srt", downloads: nil,
                rating: nil, isHearingImpaired: false, isMachineTranslated: machine,
                score: score, matchReasons: reasons)
        }
        let wrongEpisode = candidate(90, reasons: ["Farklı sezon/bölüm", "Release adı eşleşti"])
        let releaseOnly = candidate(90, reasons: ["Release adı eşleşti"])
        let machine = candidate(200, reasons: ["S01E01 eşleşti"], machine: true)
        let human = candidate(180, reasons: ["S01E01 eşleşti"])
        XCTAssertNil(SubtitleTranslationSourcePolicy.bestEnglish([wrongEpisode, releaseOnly, machine]))
        XCTAssertEqual(SubtitleTranslationSourcePolicy.bestEnglish([human, machine])?.id, human.id)
        let weakTurkish = candidate(70, reasons: ["Türkçe tercih edildi"], language: "tr")
        XCTAssertFalse(SubtitleTranslationSourcePolicy.hasGoodTurkish([weakTurkish]))
        let matchedTurkish = candidate(250, reasons: ["S01E01 eşleşti", "Türkçe tercih edildi"], language: "tr")
        XCTAssertTrue(SubtitleTranslationSourcePolicy.hasGoodTurkish([matchedTurkish]))
    }
}
