import Foundation

struct StremioSubtitleAttempt: Sendable, Equatable {
    let type: String
    let id: String
}

/// A Stremio subtitle request uses a video ID. Anime is an alternate resource
/// type for the same episode, so its IDs must retain episode coordinates.
enum StremioSubtitleRequestPlanner {
    static func attempts(
        query: SubtitleQuery,
        supportedTypes: [String],
        idPrefixes: [String]?,
        addonName: String
    ) -> [StremioSubtitleAttempt] {
        let types = query.mediaKind.stremioTypes.filter { supportedTypes.contains($0) }
        var result: [StremioSubtitleAttempt] = []
        for type in types {
            var ids = StremioClient.shared.buildContentIds(
                tmdbId: query.ids.tmdb ?? 0,
                imdbId: query.ids.imdb,
                type: type,
                season: query.season,
                episode: query.episode,
                anilistId: query.ids.anilist,
                anilistSeason: query.ids.anilist == nil ? nil : 1,
                anilistEpisode: query.animeEpisode,
                kitsuId: query.ids.kitsu,
                kitsuEpisode: query.animeEpisode,
                malId: query.ids.mal,
                malEpisode: query.animeEpisode,
                alternateSeason: query.animeSeason,
                alternateEpisode: query.animeEpisode,
                idPrefixes: idPrefixes,
                addonName: addonName
            )
            if query.isAnime {
                ids.sort { lhs, rhs in
                    let left = animeIDPriority(lhs)
                    let right = animeIDPriority(rhs)
                    return left == right ? false : left < right
                }
            }
            result += ids.map { StremioSubtitleAttempt(type: type, id: $0) }
        }
        return result
    }

    private static func animeIDPriority(_ id: String) -> Int {
        if id.hasPrefix("anilist:") { return 0 }
        if id.hasPrefix("kitsu:") { return 1 }
        if id.hasPrefix("mal:") { return 2 }
        if id.hasPrefix("tt") || id.hasPrefix("imdb:") { return 3 }
        return 4
    }
}

struct StremioAddonSubtitleProvider: SubtitleProvider {
    let id: String
    let displayName: String
    let configuredURL: String
    let supportedTypes: [String]
    let idPrefixes: [String]?

    var supportsAnime: Bool { supportedTypes.contains("anime") || supportedTypes.contains("series") }

    init(addon: StremioAddon) {
        id = "stremio:\(addon.id.uuidString)"
        displayName = addon.manifest.name
        configuredURL = addon.configuredURL
        supportedTypes = ["movie", "series", "anime"].filter {
            addon.manifest.supportsResource("subtitles", type: $0)
        }
        idPrefixes = addon.manifest.subtitleIdPrefixes
    }

    func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] {
        let subtitles = await searchRaw(query)
        return subtitles.compactMap { candidate(for: $0, query: query) }
    }

    func candidate(for subtitle: StremioSubtitle, query: SubtitleQuery) -> SubtitleCandidate? {
            guard let url = subtitle.url else { return nil }
            let candidate = SubtitleCandidate(
                id: url,
                providerID: id,
                language: subtitle.lang ?? "und",
                releaseName: subtitle.name ?? subtitle.title,
                format: URL(string: url)?.pathExtension.lowercased(),
                downloads: nil,
                rating: nil,
                isHearingImpaired: false,
                isMachineTranslated: false,
                score: 0,
                matchReasons: []
            )
            return SubtitleRanking.score(candidate, for: query)
    }

    func download(_ candidate: SubtitleCandidate) async throws -> Data {
        guard candidate.providerID == id,
              let url = URL(string: candidate.id),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw StremioClient.StremioError.invalidURL
        }
        let (data, response) = try await URLSession.shared.boundedData(
            for: URLRequest(url: url),
            maximumResponseBytes: 12 * 1_024 * 1_024
        )
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw StremioClient.StremioError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func searchRaw(_ query: SubtitleQuery) async -> [StremioSubtitle] {
        let attempts = StremioSubtitleRequestPlanner.attempts(
            query: query,
            supportedTypes: supportedTypes,
            idPrefixes: idPrefixes,
            addonName: displayName
        )
        guard !attempts.isEmpty else {
            Logger.shared.log("[SubtitleProvider] \(displayName) skipped: no compatible type/ID; titleAliases=\(query.titles.count)", type: "Stremio")
            return []
        }
        Logger.shared.log(
            "[SubtitleProvider] \(displayName) plan attempts=\(attempts.count) types=\(Set(attempts.map(\.type)).sorted()) titleAliases=\(query.titles.count) hash=\(query.videoHash != nil) size=\(query.fileSize != nil) filename=\(query.fileName != nil)",
            type: "Stremio"
        )
        var found: [StremioSubtitle] = []
        var emptyCount = 0
        var failureCount = 0
        for attempt in attempts {
            if Task.isCancelled { break }
            do {
                let fetched = try await StremioClient.shared.fetchSubtitles(
                    baseURL: configuredURL,
                    type: attempt.type,
                    id: attempt.id,
                    videoHash: query.videoHash,
                    videoSize: query.fileSize,
                    filename: query.fileName
                )
                Logger.shared.log("[SubtitleProvider] \(displayName) type=\(attempt.type) id=\(attempt.id) candidates=\(fetched.count)", type: "Stremio")
                found += fetched
                if fetched.isEmpty { emptyCount += 1 }
                if fetched.isEmpty && (query.videoHash != nil || query.fileSize != nil || query.fileName != nil) {
                    let fallback = (try? await StremioClient.shared.fetchSubtitles(
                        baseURL: configuredURL, type: attempt.type, id: attempt.id
                    )) ?? []
                    found += fallback
                    Logger.shared.log("[SubtitleProvider] \(displayName) type=\(attempt.type) ID-only fallback candidates=\(fallback.count)", type: "Stremio")
                }
            } catch {
                failureCount += 1
                Logger.shared.log("[SubtitleProvider] \(displayName) type=\(attempt.type) id=\(attempt.id) failed=\(servicePinnedNetworkErrorToken(error))", type: "Stremio")
                if query.videoHash != nil || query.fileSize != nil || query.fileName != nil {
                    found += (try? await StremioClient.shared.fetchSubtitles(
                        baseURL: configuredURL, type: attempt.type, id: attempt.id
                    )) ?? []
                }
            }
            // A subtitle endpoint returns the complete list for one video ID.
            // Prefer the first matching identity rather than delaying its UI
            // publication behind every lower-priority alias.
            if !found.isEmpty { break }
        }
        if found.isEmpty {
            Logger.shared.log("[SubtitleProvider] \(displayName) no candidates; emptyResponses=\(emptyCount) failures=\(failureCount) attempted=\(attempts.count) (identity/type mismatch remains possible)", type: "Stremio")
        }
        var seen = Set<String>()
        return found.filter { subtitle in
            guard let url = subtitle.url else { return false }
            return seen.insert(url).inserted
        }
    }
}
