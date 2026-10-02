import Foundation

struct SubtitleProviderSearchResult: Sendable {
    let providerID: String
    let candidates: [SubtitleCandidate]
    let diagnostic: String

    var sourceLabel: String {
        DirectSubtitleProviderKind(rawValue: providerID)?.displayName ?? providerID
    }
}

private actor SubtitleProviderCircuitBreaker {
    static let shared = SubtitleProviderCircuitBreaker()
    private var failures: [String: (count: Int, until: Date?)] = [:]

    func allows(_ id: String) -> Bool {
        guard let state = failures[id], let until = state.until else { return true }
        if until > Date() { return false }
        failures[id] = nil
        return true
    }

    func record(_ id: String, succeeded: Bool) {
        if succeeded {
            failures[id] = nil
        } else {
            let count = (failures[id]?.count ?? 0) + 1
            failures[id] = (count, count >= 3 ? Date().addingTimeInterval(60) : nil)
        }
    }
}

enum SubtitleProviderSearchCoordinator {
    @MainActor
    static func search(
        query: SubtitleQuery,
        providers: [any SubtitleProvider],
        onBatch: (@MainActor ([SubtitleProviderSearchResult]) -> Void)? = nil
    ) async -> [SubtitleProviderSearchResult] {
        var results: [SubtitleProviderSearchResult] = []
        await withTaskGroup(of: SubtitleProviderSearchResult.self) { group in
            for provider in providers {
                group.addTask {
                    guard await SubtitleProviderCircuitBreaker.shared.allows(provider.id) else {
                        return SubtitleProviderSearchResult(
                            providerID: provider.id, candidates: [], diagnostic: "circuit-open"
                        )
                    }
                    do {
                        let candidates = try await retryOnce(provider: provider, query: query)
                        await SubtitleProviderCircuitBreaker.shared.record(provider.id, succeeded: true)
                        return SubtitleProviderSearchResult(
                            providerID: provider.id, candidates: candidates,
                            diagnostic: candidates.isEmpty ? "valid-empty-response" : "matched"
                        )
                    } catch {
                        if !(error is CancellationError) {
                            await SubtitleProviderCircuitBreaker.shared.record(provider.id, succeeded: false)
                        }
                        return SubtitleProviderSearchResult(
                            providerID: provider.id, candidates: [],
                            diagnostic: error is CancellationError ? "cancelled" : "request-or-parse-failed"
                        )
                    }
                }
            }
            for await batch in group {
                if Task.isCancelled { group.cancelAll(); break }
                results.append(batch)
                Logger.shared.log("[SubtitleProvider] id=\(batch.providerID) candidates=\(batch.candidates.count) outcome=\(batch.diagnostic)", type: "Player")
                onBatch?(results)
            }
        }
        return results
    }

    private static func retryOnce(provider: any SubtitleProvider, query: SubtitleQuery) async throws -> [SubtitleCandidate] {
        do {
            return try await timedSearch(provider: provider, query: query)
        } catch let error as URLError where error.code == .networkConnectionLost {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 200_000_000)
            return try await timedSearch(provider: provider, query: query)
        }
    }

    private static func timedSearch(provider: any SubtitleProvider, query: SubtitleQuery) async throws -> [SubtitleCandidate] {
        try await withThrowingTaskGroup(of: [SubtitleCandidate].self) { group in
            group.addTask { try await provider.search(query) }
            group.addTask {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { return [] }
            return first
        }
    }
}
