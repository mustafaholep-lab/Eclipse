import Foundation

enum SubtitleMediaKind: String, Sendable {
    case unknown
    case movie
    case series
    case anime

    /// Stremio anime is a second request type for a series, not a replacement
    /// for the existing series endpoint.
    var stremioTypes: [String] {
        switch self {
        case .anime: return ["series", "anime"]
        case .unknown: return []
        default: return [rawValue]
        }
    }
}

struct SubtitleMediaIDs: Sendable, Equatable {
    var imdb: String? = nil
    var tmdb: Int? = nil
    var kitsu: Int? = nil
    var anilist: Int? = nil
    var mal: Int? = nil
    var tvdb: Int? = nil
    var anidb: Int? = nil

    var seriesCacheKey: String? {
        if let anilist, anilist > 0 { return "anilist:\(anilist)" }
        if let imdb, !imdb.isEmpty { return "imdb:\(imdb.lowercased())" }
        if let tmdb, tmdb > 0 { return "tmdb:\(tmdb)" }
        if let kitsu, kitsu > 0 { return "kitsu:\(kitsu)" }
        if let mal, mal > 0 { return "mal:\(mal)" }
        if let tvdb, tvdb > 0 { return "tvdb:\(tvdb)" }
        if let anidb, anidb > 0 { return "anidb:\(anidb)" }
        return nil
    }
}

struct SubtitleTitleVariant: Sendable, Equatable {
    enum Origin: String, Sendable {
        case displayed, romaji, english, native, synonym, original, base
    }

    let value: String
    let origin: Origin
    let normalized: String
}

struct SubtitleQuery: Sendable {
    let mediaKind: SubtitleMediaKind
    let isAnime: Bool
    var ids: SubtitleMediaIDs
    var season: Int?
    var episode: Int?
    /// The AniList/Kitsu/MAL entry's own episode coordinate, which may differ
    /// from the parent TMDB show's season and episode.
    var animeSeason: Int?
    var animeEpisode: Int?
    var absoluteEpisode: Int?
    var year: Int?
    var titles: [SubtitleTitleVariant]
    var fileName: String?
    var releaseName: String?
    var videoHash: String?
    var fileSize: Int64?
    var duration: Double?
    var preferredLanguages: [String] = ["tr", "en"]
    var preferredReleaseTokens: [String] = []

    var seriesCacheKey: String? {
        if let key = ids.seriesCacheKey { return key }
        return titles.first.map { "title:\($0.normalized)" }
    }
}

struct SubtitleCandidate: Sendable {
    /// The provider owns this opaque identifier, including any download token.
    let id: String
    let providerID: String
    let language: String
    let releaseName: String?
    let format: String?
    let downloads: Int?
    let rating: Double?
    let isHearingImpaired: Bool
    let isMachineTranslated: Bool
    var score: Int
    var matchReasons: [String]
    var videoHash: String? = nil
}

/// Keeps automatic track choice separate from an explicit player-menu choice.
/// A search may replace a fallback track, but never a preferred embedded track
/// or a track the viewer selected themselves.
struct SubtitlePlaybackSelection: Equatable {
    enum Choice: Equatable { case none, automaticPreferred, automaticFallback, user }
    private(set) var choice: Choice = .none
    private(set) var generation = 0

    mutating func beginMedia() {
        generation += 1
        choice = .none
    }

    mutating func selectAutomatically(preferred: Bool) {
        guard choice != .user else { return }
        choice = preferred ? .automaticPreferred : .automaticFallback
    }

    mutating func selectByUser() { choice = .user }

    var mayChooseDefault: Bool { choice == .none }
    var mayApplyProviderResult: Bool { choice == .none || choice == .automaticFallback }
    func acceptsResult(generation expected: Int) -> Bool { generation == expected }
}

/// Applies the viewer's search edits without changing AniMap's separate TMDB
/// and anime episode coordinates. Only explicitly edited coordinates change.
struct SubtitleManualSearch: Equatable {
    var title: String
    var season: Int?
    var episode: Int?
    var absoluteEpisode: Int?
    var language: String

    func applying(to original: SubtitleQuery) -> SubtitleQuery {
        var query = original
        let chosenTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosenTitle.isEmpty {
            query.titles = SubtitleTitlePolicy.variants(
                [(chosenTitle, .displayed)] + original.titles.map { ($0.value, $0.origin) }
            )
        }
        if let season, season >= 0 { query.season = season; query.animeSeason = season }
        if let episode, episode > 0 { query.episode = episode; query.animeEpisode = episode }
        if let absoluteEpisode, absoluteEpisode > 0 {
            query.absoluteEpisode = absoluteEpisode
            // Only an explicit change may override AniMap's local anime
            // coordinate. TMDB/IMDb still use the season and episode above.
            if absoluteEpisode != original.absoluteEpisode {
                query.animeEpisode = absoluteEpisode
            }
        }
        let chosenLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !chosenLanguage.isEmpty { query.preferredLanguages = [chosenLanguage] }
        return query
    }
}

enum SubtitlePreferenceKey {
    static func choice(mediaKey: String) -> String {
        "subtitleChoice.\(mediaKey)"
    }

    /// The full selected release label, including provider and filename, must
    /// match before a saved delay is restored. A different encode starts at 0.
    static func delay(mediaKey: String, releaseLabel: String) -> String? {
        let trimmed = releaseLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in trimmed.lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return "subtitleDelay.\(mediaKey).\(String(hash, radix: 16))"
    }
}

protocol SubtitleProvider: Sendable {
    var id: String { get }
    var supportsAnime: Bool { get }
    func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate]
    func download(_ candidate: SubtitleCandidate) async throws -> Data
}

enum SubtitleTitlePolicy {
    private static let seasonSuffixes = [
        #"(?i)\s+(?:\d+(?:st|nd|rd|th)\s+season|season\s+\d+|part\s+(?:\d+|[IVX]+)|cour\s+(?:\d+|[IVX]+))$"#,
        #"(?i)\s+\(TV\)$"#
    ]

    static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func baseTitle(_ title: String) -> String? {
        var base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in seasonSuffixes.reversed() {
            base = base.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let original = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty || normalized(base) == normalized(original) ? nil : base
    }

    static func variants(_ candidates: [(String, SubtitleTitleVariant.Origin)], limit: Int = 6) -> [SubtitleTitleVariant] {
        var seen = Set<String>()
        var result: [SubtitleTitleVariant] = []
        for (raw, origin) in candidates {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized(value)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(.init(value: value, origin: origin, normalized: key))
            if result.count >= max(1, limit) { break }
        }
        return result
    }
}

/// Only a coordinate already established by EpisodePlaybackContext can anchor
/// an absolute conversion. Missing cours and sequel lengths remain unknown.
struct SubtitleEpisodeMapping: Sendable {
    let season: Int
    let localEpisode: Int
    let absoluteEpisode: Int
    let knownSeasonEpisodeCount: Int?

    init?(context: EpisodePlaybackContext) {
        guard context.localSeasonNumber >= 0,
              context.localEpisodeNumber > 0,
              let absolute = context.animeAbsoluteEpisodeNumber,
              absolute > 0 else { return nil }
        season = context.localSeasonNumber
        localEpisode = context.localEpisodeNumber
        absoluteEpisode = absolute
        knownSeasonEpisodeCount = context.animeSeasonEpisodeCount
    }

    func absolute(season requestedSeason: Int, episode requestedEpisode: Int) -> Int? {
        guard requestedSeason == season, requestedEpisode > 0,
              knownSeasonEpisodeCount.map({ requestedEpisode <= $0 }) ?? (requestedEpisode == localEpisode) else { return nil }
        let (base, subtractOverflow) = absoluteEpisode.subtractingReportingOverflow(localEpisode)
        let (value, addOverflow) = base.addingReportingOverflow(requestedEpisode)
        return subtractOverflow || addOverflow || value <= 0 ? nil : value
    }

    func coordinate(absolute requestedAbsolute: Int) -> (season: Int, episode: Int)? {
        guard requestedAbsolute > 0 else { return nil }
        let (difference, overflow) = requestedAbsolute.subtractingReportingOverflow(absoluteEpisode)
        let (value, addOverflow) = localEpisode.addingReportingOverflow(difference)
        guard !overflow, !addOverflow, value > 0,
              knownSeasonEpisodeCount.map({ value <= $0 }) ?? (value == localEpisode) else { return nil }
        return (season, value)
    }
}

enum SubtitleEpisodeQueryPolicy {
    static func variants(season: Int?, episode: Int?, absoluteEpisode: Int?) -> [String] {
        var result: [String] = []
        if let season, let episode, season >= 0, episode > 0 {
            result.append(String(format: "S%02dE%02d", season, episode))
        }
        if let episode, episode > 0 {
            result += [String(episode), "EP\(episode)", "E\(episode)", "Episode \(episode)"]
        }
        if let absoluteEpisode, absoluteEpisode > 0 { result.append(String(absoluteEpisode)) }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }
}
