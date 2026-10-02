import Foundation

struct SubtitleAnimeIdentity: Sendable {
    let anilist: Int
    let mal: Int?
    let kitsu: Int?
    let romaji: String?
    let english: String?
    let native: String?
    let synonyms: [String]

    init(anilist: Int, mal: Int?, kitsu: Int?, romaji: String?, english: String?, native: String?, synonyms: [String]) {
        self.anilist = anilist
        self.mal = mal
        self.kitsu = kitsu
        self.romaji = romaji
        self.english = english
        self.native = native
        self.synonyms = synonyms
    }

    init(_ identity: AniListSeasonIdentity) {
        anilist = identity.anilistId
        mal = identity.malId
        kitsu = identity.kitsuId
        romaji = identity.romajiTitle
        english = identity.englishTitle
        native = identity.nativeTitle
        synonyms = identity.synonyms
    }
}

/// Cache only series metadata. Episode coordinates and the selected release
/// always come from the current PlaybackRequest and are never cached here.
actor SubtitleMetadataCache {
    private struct Entry {
        let value: SubtitleAnimeIdentity
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var pending: [String: Task<SubtitleAnimeIdentity?, Never>] = [:]
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 30 * 60) {
        self.lifetime = lifetime
    }

    func value(
        for key: String,
        load: @escaping @Sendable () async -> SubtitleAnimeIdentity?
    ) async -> SubtitleAnimeIdentity? {
        guard !Task.isCancelled else { return nil }
        if let entry = entries[key], entry.expiresAt > Date() { return entry.value }
        if let running = pending[key] { return await running.value }
        let task = Task { await load() }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        if let result, !Task.isCancelled {
            if entries.count >= 256 {
                entries = entries.filter { $0.value.expiresAt > Date() }
                if entries.count >= 256 { entries.removeAll() }
            }
            entries[key] = Entry(value: result, expiresAt: Date().addingTimeInterval(lifetime))
        }
        return Task.isCancelled ? nil : result
    }
}

@MainActor
final class SubtitleMetadataResolver {
    static let shared = SubtitleMetadataResolver()
    typealias IdentityLoader = @Sendable (Int) async -> SubtitleAnimeIdentity?

    private let identityLoader: IdentityLoader
    private let cache: SubtitleMetadataCache

    init(
        cache: SubtitleMetadataCache = SubtitleMetadataCache(),
        identityLoader: @escaping IdentityLoader = { id in
            guard let identity = await AniListService.shared.fetchAnimeSeasonIdentity(anilistId: id) else {
                return nil
            }
            return SubtitleAnimeIdentity(identity)
        }
    ) {
        self.cache = cache
        self.identityLoader = identityLoader
    }

    func resolve(request: PlaybackRequest, duration: Double? = nil) async -> SubtitleQuery {
        let context = request.episodePlaybackContext
        let fingerprint = request.launchContext?.streamFingerprint
        var sourceTitles: [(String, SubtitleTitleVariant.Origin)] = []
        let mediaKind: SubtitleMediaKind
        let animeContent: Bool
        let tmdbID: Int?
        let localSeason: Int?
        let localEpisode: Int?

        switch request.mediaInfo {
        case .movie(let id, let title, _, let isAnime):
            mediaKind = .movie
            animeContent = request.isAnime || isAnime
            tmdbID = id
            localSeason = nil
            localEpisode = nil
            sourceTitles.append((title, .displayed))
        case .episode(let id, let season, let episode, let title, _, let isAnime):
            animeContent = request.isAnime || isAnime || context?.hasAnimeMediaId == true
            mediaKind = animeContent ? .anime : .series
            tmdbID = id
            localSeason = season
            localEpisode = episode
            if let title { sourceTitles.append((title, .displayed)) }
        case nil:
            mediaKind = .unknown
            animeContent = request.isAnime
            tmdbID = nil
            localSeason = nil
            localEpisode = nil
        }

        sourceTitles.append((request.title, .displayed))
        if let original = request.servicesOriginalTitle { sourceTitles.append((original, .original)) }
        let streamTitleCandidates: [(String, SubtitleTitleVariant.Origin)] =
            (request.launchContext?.titleCandidates ?? []).map { ($0, .synonym) }

        var query = SubtitleQuery(
            mediaKind: mediaKind,
            isAnime: animeContent,
            ids: SubtitleMediaIDs(
                imdb: request.imdbID,
                tmdb: tmdbID,
                kitsu: context?.kitsuMediaId,
                anilist: context?.positiveAniListMediaId,
                mal: context?.exactMALMediaId,
                tvdb: nil,
                anidb: nil
            ),
            season: context?.resolvedTMDBSeasonNumber ?? request.originalTMDBSeasonNumber ?? localSeason,
            episode: context?.resolvedTMDBEpisodeNumber ?? request.originalTMDBEpisodeNumber ?? localEpisode,
            animeSeason: context?.localSeasonNumber,
            animeEpisode: context?.localEpisodeNumber,
            absoluteEpisode: context?.animeAbsoluteEpisodeNumber,
            year: request.mediaYear,
            titles: [],
            fileName: fingerprint?.filename ?? fingerprint?.labels.first(where: {
                let value = $0.lowercased()
                return [".mkv", ".mp4", ".avi", ".webm"].contains(where: value.contains)
            }),
            releaseName: request.launchContext?.streamName ?? fingerprint?.labels.first,
            videoHash: fingerprint?.videoHash,
            fileSize: fingerprint?.videoSize,
            duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        )

        if let anilistID = query.ids.anilist, anilistID > 0,
           let key = query.ids.seriesCacheKey {
            let loader = identityLoader
            if let identity = await cache.value(for: key, load: { await loader(anilistID) }),
               !Task.isCancelled {
                if query.ids.mal == nil { query.ids.mal = identity.mal }
                if query.ids.kitsu == nil { query.ids.kitsu = identity.kitsu }
                if let romaji = identity.romaji { sourceTitles.append((romaji, .romaji)) }
                if let english = identity.english { sourceTitles.append((english, .english)) }
                if let native = identity.native { sourceTitles.append((native, .native)) }
                sourceTitles += identity.synonyms.map { ($0, .synonym) }
            }
        }

        if let first = sourceTitles.first, let base = SubtitleTitlePolicy.baseTitle(first.0) {
            sourceTitles.insert((base, .base), at: 1)
        }
        sourceTitles += streamTitleCandidates
        query.titles = SubtitleTitlePolicy.variants(sourceTitles)
        return query
    }
}
