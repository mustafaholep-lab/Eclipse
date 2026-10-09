import Foundation

/// OpenSubtitles.com REST API v1. Search needs an application API key;
/// obtaining a temporary download link additionally needs a user bearer token.
struct OpenSubtitlesRESTProvider: SubtitleProvider {
    let id = "opensubtitles-rest"
    let supportsAnime = true
    let apiKey: String
    let bearerToken: String?

    private struct SearchResponse: Decodable {
        let data: [Result]
    }

    private struct Result: Decodable {
        let attributes: Attributes
    }

    private struct Attributes: Decodable {
        let language: String?
        let release: String?
        let download_count: Int?
        let ratings: Double?
        let hearing_impaired: Bool?
        let machine_translated: Bool?
        let ai_translated: Bool?
        let moviehash_match: Bool?
        let files: [File]?
    }

    private struct File: Decodable {
        let file_id: Int?
        let file_name: String?
    }

    private struct DownloadResponse: Decodable {
        let link: String
    }

    func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] {
        guard !apiKey.isEmpty else { return [] }
        var results: [SubtitleCandidate] = []
        var seen = Set<Int>()
        for url in searchURLs(query: query) {
            try Task.checkCancellation()
            let data = try await requestData(URLRequest(url: url, timeoutInterval: 8), maximumBytes: 2 * 1_024 * 1_024)
            for candidate in try decodeCandidates(data, query: query) where SubtitleRanking.accepts(candidate) {
                if let fileID = Int(candidate.id), seen.insert(fileID).inserted { results.append(candidate) }
            }
            if !results.isEmpty { break }
        }
        return results.sorted { $0.score > $1.score }
    }

    func download(_ candidate: SubtitleCandidate) async throws -> Data {
        guard candidate.providerID == id, let fileID = Int(candidate.id), fileID > 0 else {
            throw OpenSubtitlesRESTError.invalidFileID
        }
        guard bearerToken?.isEmpty == false else { throw OpenSubtitlesRESTError.loginRequired }
        let url = URL(string: "https://api.opensubtitles.com/api/v1/download")!
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileID])
        let data = try await requestData(request, maximumBytes: 512 * 1_024, userAuthenticated: true)
        let response = try JSONDecoder().decode(DownloadResponse.self, from: data)
        guard let downloadURL = URL(string: response.link), downloadURL.scheme == "https" else {
            throw OpenSubtitlesRESTError.invalidDownloadLink
        }
        // The signed temporary file URL is a separate origin; never forward
        // the API key or bearer token to it.
        var fileRequest = URLRequest(url: downloadURL, timeoutInterval: 15)
        fileRequest.setValue("Eclipse/6 subtitle-provider", forHTTPHeaderField: "User-Agent")
        let (fileData, fileResponse) = try await URLSession.shared.boundedData(
            for: fileRequest, maximumResponseBytes: SubtitleFileHandling.maximumBytes
        )
        guard let http = fileResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return fileData
    }

    func testConnection() async throws {
        guard !apiKey.isEmpty else { throw OpenSubtitlesRESTError.missingKey }
        let url = URL(string: "https://api.opensubtitles.com/api/v1/subtitles?query=EclipseConnectionTest")!
        let data = try await requestData(URLRequest(url: url, timeoutInterval: 8), maximumBytes: 256 * 1_024)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            throw OpenSubtitlesRESTError.invalidKey
        }
        if bearerToken?.isEmpty == false {
            let accountURL = URL(string: "https://api.opensubtitles.com/api/v1/infos/user")!
            let accountData = try await requestData(
                URLRequest(url: accountURL, timeoutInterval: 8),
                maximumBytes: 256 * 1_024,
                userAuthenticated: true
            )
            guard (try? JSONSerialization.jsonObject(with: accountData)) is [String: Any] else {
                throw OpenSubtitlesRESTError.invalidKey
            }
        }
    }

    func searchURLs(query: SubtitleQuery) -> [URL] {
        var urls: [URL] = []
        func append(_ search: URLQueryItem) {
            var components = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")!
            var items = [search, URLQueryItem(name: "languages", value: "tr,en")]
            if query.mediaKind != .movie {
                if let season = query.season { items.append(.init(name: "season_number", value: String(season))) }
                if let episode = query.episode { items.append(.init(name: "episode_number", value: String(episode))) }
            }
            components.queryItems = items
            if let url = components.url { urls.append(url) }
        }
        if let hash = query.videoHash, hash.range(of: #"^[a-fA-F0-9]{16}$"#, options: .regularExpression) != nil {
            append(.init(name: "moviehash", value: hash.lowercased()))
        }
        if let imdb = query.ids.imdb {
            let digits = imdb.lowercased().replacingOccurrences(of: "tt", with: "")
            if Int(digits) != nil { append(.init(name: query.mediaKind == .movie ? "imdb_id" : "parent_imdb_id", value: digits)) }
        }
        if let tmdb = query.ids.tmdb, tmdb > 0 {
            append(.init(name: query.mediaKind == .movie ? "tmdb_id" : "parent_tmdb_id", value: String(tmdb)))
        }
        for title in query.titles.prefix(4) { append(.init(name: "query", value: title.value)) }
        return urls
    }

    func decodeCandidates(_ data: Data, query: SubtitleQuery) throws -> [SubtitleCandidate] {
        try JSONDecoder().decode(SearchResponse.self, from: data).data.flatMap { item in
            (item.attributes.files ?? []).compactMap { file -> SubtitleCandidate? in
                guard let fileID = file.file_id, fileID > 0 else { return nil }
                let raw = SubtitleCandidate(
                    id: String(fileID), providerID: id,
                    language: item.attributes.language ?? "und",
                    releaseName: item.attributes.release ?? file.file_name,
                    format: file.file_name.flatMap { ($0 as NSString).pathExtension },
                    downloads: item.attributes.download_count,
                    rating: item.attributes.ratings,
                    isHearingImpaired: item.attributes.hearing_impaired ?? false,
                    isMachineTranslated: item.attributes.machine_translated == true
                        || item.attributes.ai_translated == true,
                    score: 0, matchReasons: [],
                    videoHash: item.attributes.moviehash_match == true ? query.videoHash : nil
                )
                return SubtitleRanking.score(raw, for: query)
            }
        }
    }

    private func requestData(_ original: URLRequest, maximumBytes: Int, userAuthenticated: Bool = false) async throws -> Data {
        var request = original
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("Eclipse/6 subtitle-provider", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if userAuthenticated, let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.boundedData(
            for: request, maximumResponseBytes: maximumBytes
        )
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 || http.statusCode == 403 { throw OpenSubtitlesRESTError.invalidKey }
        if http.statusCode == 429 { throw OpenSubtitlesRESTError.rateLimited }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
}

enum OpenSubtitlesRESTError: LocalizedError {
    case missingKey, invalidKey, loginRequired, invalidFileID, invalidDownloadLink, rateLimited

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Enter an OpenSubtitles API key first."
        case .invalidKey: return "OpenSubtitles did not accept the API credentials."
        case .loginRequired: return "Sign in to OpenSubtitles before downloading."
        case .invalidFileID: return "OpenSubtitles returned an invalid subtitle file."
        case .invalidDownloadLink: return "OpenSubtitles returned an invalid download link."
        case .rateLimited: return "OpenSubtitles request limit reached. Try again later."
        }
    }
}
