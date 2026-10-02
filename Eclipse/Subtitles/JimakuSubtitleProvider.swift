import Foundation

/// Direct Jimaku API integration. Entry IDs and episode coordinates come from
/// the existing SubtitleQuery resolver rather than a second anime map.
struct JimakuSubtitleProvider: SubtitleProvider {
    let id = "jimaku"
    let supportsAnime = true
    let apiKey: String

    private struct Entry: Decodable {
        let id: Int64
        let anilist_id: Int?
        let tmdb_id: String?
    }

    private struct FileEntry: Decodable {
        let name: String
        let size: Int64
        let url: String
    }

    func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] {
        guard !apiKey.isEmpty else { return [] }
        let searches = searchURLs(query: query)
        var entries: [Entry] = []
        for url in searches {
            try Task.checkCancellation()
            let data = try await get(url, maximumBytes: 512 * 1_024)
            entries = try JSONDecoder().decode([Entry].self, from: data)
            if !entries.isEmpty { break }
        }
        guard !entries.isEmpty else { return [] }
        var results: [SubtitleCandidate] = []
        var seen = Set<String>()
        for entry in entries.prefix(3) {
            guard let url = filesURL(entryID: entry.id, episode: query.animeEpisode ?? query.episode) else { continue }
            let data = try await get(url, maximumBytes: 2 * 1_024 * 1_024)
            for candidate in try decodeCandidates(data, query: query) where seen.insert(candidate.id).inserted {
                results.append(candidate)
            }
        }
        return results.sorted { $0.score > $1.score }
    }

    func download(_ candidate: SubtitleCandidate) async throws -> Data {
        guard candidate.providerID == id,
              let url = URL(string: candidate.id), url.scheme == "https" else {
            throw JimakuError.invalidDownloadURL
        }
        return try await get(url, maximumBytes: SubtitleFileHandling.maximumBytes, authenticated: false)
    }

    func testConnection() async throws {
        guard !apiKey.isEmpty else { throw JimakuError.missingKey }
        let url = URL(string: "https://jimaku.cc/api/entries/search?anilist_id=1")!
        let data = try await get(url, maximumBytes: 512 * 1_024)
        guard (try? JSONSerialization.jsonObject(with: data)) is [Any] else {
            throw JimakuError.invalidKey
        }
    }

    func searchURLs(query: SubtitleQuery) -> [URL] {
        var urls: [URL] = []
        func append(_ items: [URLQueryItem]) {
            var components = URLComponents(string: "https://jimaku.cc/api/entries/search")!
            components.queryItems = items
            if let url = components.url { urls.append(url) }
        }
        if let anilist = query.ids.anilist, anilist > 0 {
            append([.init(name: "anilist_id", value: String(anilist))])
        }
        if let tmdb = query.ids.tmdb, tmdb > 0 {
            append([.init(name: "tmdb_id", value: "\(query.mediaKind == .movie ? "movie" : "tv"):\(tmdb)")])
        }
        for title in query.titles.prefix(4) {
            append([.init(name: "query", value: title.value),
                    .init(name: "anime", value: query.isAnime ? "true" : "false")])
        }
        return urls
    }

    func filesURL(entryID: Int64, episode: Int?) -> URL? {
        guard entryID > 0 else { return nil }
        var components = URLComponents(string: "https://jimaku.cc/api/entries/\(entryID)/files")!
        if let episode, episode > 0 {
            components.queryItems = [.init(name: "episode", value: String(episode))]
        }
        return components.url
    }

    func decodeCandidates(_ data: Data, query: SubtitleQuery) throws -> [SubtitleCandidate] {
        try JSONDecoder().decode([FileEntry].self, from: data).compactMap { file in
            guard let url = URL(string: file.url), url.scheme == "https",
                  file.size > 0, file.size <= Int64(SubtitleFileHandling.maximumBytes) else { return nil }
            let lower = file.name.lowercased()
            let language = lower.contains(".eng.") || lower.contains(".en.")
                ? "eng" : (lower.contains(".tur.") || lower.contains(".tr.") ? "tur" : "jpn")
            let raw = SubtitleCandidate(
                id: url.absoluteString, providerID: id, language: language,
                releaseName: file.name, format: (file.name as NSString).pathExtension,
                downloads: nil, rating: nil, isHearingImpaired: false,
                isMachineTranslated: false, score: 0, matchReasons: []
            )
            return SubtitleRanking.score(raw, for: query)
        }
    }

    private func get(_ url: URL, maximumBytes: Int, authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 8)
        if authenticated { request.setValue(apiKey, forHTTPHeaderField: "Authorization") }
        request.setValue("Eclipse/6 subtitle-provider", forHTTPHeaderField: "User-Agent")
        if authenticated { request.setValue("application/json", forHTTPHeaderField: "Accept") }
        let (data, response) = try await URLSession.shared.boundedData(
            for: request, maximumResponseBytes: maximumBytes
        )
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if authenticated && http.statusCode == 401 { throw JimakuError.invalidKey }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
}

enum JimakuError: LocalizedError {
    case missingKey, invalidKey, invalidDownloadURL

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Enter a Jimaku API key first."
        case .invalidKey: return "Jimaku did not accept this API key."
        case .invalidDownloadURL: return "Jimaku returned an invalid download URL."
        }
    }
}
