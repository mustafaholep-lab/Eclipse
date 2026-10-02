import Foundation

/// Direct SubDL API v1 integration. The API key is supplied by the caller and
/// is never included in candidate identifiers or diagnostic output.
struct SubDLSubtitleProvider: SubtitleProvider {
    let id = "subdl"
    let supportsAnime = true
    let apiKey: String

    private struct Response: Decodable {
        let status: Bool
        let subtitles: [Item]?
        let error: String?
    }

    private struct Item: Decodable {
        let name: String?
        let release_name: String?
        let url: String?
        let language: String?
        let hi: Bool?
        let format: String?
        let unpack_files: [Item]?
    }

    func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let names = query.titles.prefix(4).map(\.value)
        var searches: [String?] = [nil]
        if query.ids.imdb == nil && query.ids.tmdb == nil { searches = names.map(Optional.some) }
        else { searches += names.map(Optional.some) }
        var seen = Set<String>()
        var candidates: [SubtitleCandidate] = []

        for title in searches {
            try Task.checkCancellation()
            guard let url = requestURL(query: query, title: title) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Eclipse/6 subtitle-provider", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.boundedData(
                for: request, maximumResponseBytes: 2 * 1_024 * 1_024
            )
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            for candidate in try decodeCandidates(data, query: query) {
                if seen.insert(candidate.id).inserted { candidates.append(candidate) }
            }
            if !candidates.isEmpty { break }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    func download(_ candidate: SubtitleCandidate) async throws -> Data {
        guard candidate.providerID == id, let url = downloadURL(candidate.id) else {
            throw SubDLError.invalidDownloadURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Eclipse/6 subtitle-provider", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.boundedData(
            for: request, maximumResponseBytes: SubtitleFileHandling.maximumBytes
        )
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func testConnection() async throws {
        guard !apiKey.isEmpty else { throw SubDLError.missingKey }
        var components = URLComponents(string: "https://api.subdl.com/api/v1/me")!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Eclipse/6 subtitle-provider", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.boundedData(
            for: request, maximumResponseBytes: 512 * 1_024
        )
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw SubDLError.invalidKey
        }
    }

    func requestURL(query: SubtitleQuery, title: String?) -> URL? {
        var components = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")!
        var items = [URLQueryItem(name: "api_key", value: apiKey)]
        if let title, !title.isEmpty { items.append(.init(name: "film_name", value: title)) }
        else if let imdb = query.ids.imdb { items.append(.init(name: "imdb_id", value: imdb)) }
        else if let tmdb = query.ids.tmdb, tmdb > 0 { items.append(.init(name: "tmdb_id", value: String(tmdb))) }
        else if let name = query.fileName { items.append(.init(name: "file_name", value: name)) }
        else { return nil }
        items.append(.init(name: "type", value: query.mediaKind == .movie ? "movie" : "tv"))
        if query.mediaKind != .movie {
            if let season = query.season { items.append(.init(name: "season_number", value: String(season))) }
            if let episode = query.episode { items.append(.init(name: "episode_number", value: String(episode))) }
        }
        if let year = query.year { items.append(.init(name: "year", value: String(year))) }
        items += [
            .init(name: "languages", value: "TR,EN"),
            .init(name: "unpack", value: "1"),
            .init(name: "subs_per_page", value: "30"),
            .init(name: "client", value: "custom_integration")
        ]
        components.queryItems = items
        return components.url
    }

    func decodeCandidates(_ data: Data, query: SubtitleQuery) throws -> [SubtitleCandidate] {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.status else { throw SubDLError.providerRejected }
        var candidates: [SubtitleCandidate] = []
        for item in decoded.subtitles ?? [] {
            for file in item.unpack_files?.isEmpty == false ? (item.unpack_files ?? []) : [item] {
                guard let url = downloadURL(file.url) else { continue }
                let raw = SubtitleCandidate(
                    id: url.absoluteString, providerID: id,
                    language: file.language ?? item.language ?? "und",
                    releaseName: file.release_name ?? item.release_name ?? file.name ?? item.name,
                    format: file.format ?? URL(string: file.name ?? item.name ?? "")?.pathExtension,
                    downloads: nil, rating: nil,
                    isHearingImpaired: file.hi ?? item.hi ?? false,
                    isMachineTranslated: false, score: 0, matchReasons: []
                )
                candidates.append(SubtitleRanking.score(raw, for: query))
            }
        }
        return candidates
    }

    private func downloadURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        let url = URL(string: value, relativeTo: URL(string: "https://dl.subdl.com"))?.absoluteURL
        guard url?.scheme == "https", url?.host == "dl.subdl.com",
              url?.path.hasPrefix("/subtitle/") == true else { return nil }
        return url
    }
}

enum SubDLError: LocalizedError {
    case missingKey, invalidKey, invalidDownloadURL, providerRejected

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Enter a SubDL API key first."
        case .invalidKey: return "SubDL did not accept this API key."
        case .invalidDownloadURL: return "SubDL returned an invalid download URL."
        case .providerRejected: return "SubDL search was rejected. Check the API key or quota."
        }
    }
}
