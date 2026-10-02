import Foundation

struct SubtitleReleaseName: Sendable, Equatable {
    let title: String?
    let season: Int?
    let episode: Int?
    let absoluteEpisode: Int?
    let revision: Int?
    let group: String?
    let source: String?
    let resolution: String?

    static func parse(_ name: String?) -> SubtitleReleaseName {
        let value = name ?? ""
        let lower = value.lowercased()
        let seasonEpisode = capture(#"(?i)(?:^|[^a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?:[^0-9]|$)"#, in: value)
        let episodeToken = seasonEpisode == nil
            ? capture(#"(?i)(?:^|[^a-z0-9])(?:ep|episode|e)[ ._-]*(\d{1,3})(?:v\d+)?(?:[^0-9]|$)"#, in: value)
            : nil
        let animeDash = seasonEpisode == nil && episodeToken == nil
            ? capture(#"(?i)(?:^|[ ._])-[ ._]*(\d{1,3})(?:v\d+)?(?:[^0-9]|$)"#, in: value)
            : nil
        let group = capture(#"^\[([^\]]{1,40})\]"#, in: value)?.first
        let source = ["web-dl", "webrip", "blu-ray", "bluray", "bdrip", "hdtv", "dvd"]
            .first(where: lower.contains)
        let resolution = ["2160p", "1080p", "720p", "480p"].first(where: lower.contains)
        let revision = capture(#"(?i)(?:^|[^a-z])v(\d{1,2})(?:[^0-9]|$)"#, in: value)?
            .first.flatMap(Int.init)
        let title = releaseTitle(value)
        return SubtitleReleaseName(
            title: title,
            season: seasonEpisode?.first.flatMap(Int.init),
            episode: seasonEpisode?.dropFirst().first.flatMap(Int.init),
            absoluteEpisode: (episodeToken ?? animeDash)?.first.flatMap(Int.init),
            revision: revision,
            group: group,
            source: source,
            resolution: resolution
        )
    }

    private static func releaseTitle(_ value: String) -> String? {
        var source = value.replacingOccurrences(of: #"^\[[^\]]{1,40}\]\s*"#, with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(
            pattern: #"(?i)(?:s\d{1,2}[ ._-]*e\d{1,3}|[ ._]-[ ._]*\d{1,3}|(?:^|[^a-z0-9])(?:ep|episode|e)[ ._-]*\d{1,3}|(?:^|[^a-z0-9])(?:2160p|1080p|720p|480p))"#
        ), let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let range = Range(match.range, in: source) {
            source = String(source[..<range.lowerBound])
        }
        let title = source.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-[]")))
        return title.isEmpty ? nil : title
    }

    private static func capture(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }
}

enum SubtitleRanking {
    static func accepts(_ candidate: SubtitleCandidate) -> Bool {
        if candidate.matchReasons.contains("Video hash eşleşti") { return true }
        return !candidate.matchReasons.contains("Farklı sezon/bölüm")
            && !candidate.matchReasons.contains("Farklı bölüm numarası")
    }

    static func score(_ candidate: SubtitleCandidate, for query: SubtitleQuery) -> SubtitleCandidate {
        var result = candidate
        var score = 0
        var reasons: [String] = []
        let subtitle = SubtitleReleaseName.parse(candidate.releaseName)
        let release = SubtitleReleaseName.parse(query.releaseName ?? query.fileName)

        if let expected = query.videoHash?.lowercased(),
           let actual = candidate.videoHash?.lowercased(), actual == expected {
            score += 1_000
            reasons.append("Video hash eşleşti")
        }
        if let season = subtitle.season, let episode = subtitle.episode {
            if season == query.season && episode == query.episode {
                score += 180
                reasons.append(String(format: "S%02dE%02d eşleşti", season, episode))
            } else {
                score -= 500
                reasons.append("Farklı sezon/bölüm")
            }
        } else if let absolute = subtitle.absoluteEpisode {
            if absolute == query.absoluteEpisode || absolute == query.animeEpisode || absolute == query.episode {
                score += 160
                reasons.append("Absolute episode \(absolute) eşleşti")
            } else {
                score -= 450
                reasons.append("Farklı bölüm numarası")
            }
        }
        if let group = subtitle.group, let expected = release.group,
           group.caseInsensitiveCompare(expected) == .orderedSame {
            score += 35
            reasons.append("Release group eşleşti")
        }
        if let source = subtitle.source, source == release.source {
            score += 25
            reasons.append("\(source.uppercased()) kaynağı eşleşti")
        }
        if let resolution = subtitle.resolution, resolution == release.resolution {
            score += 8
            reasons.append("Çözünürlük eşleşti")
        }
        let subtitleTokens = tokens(candidate.releaseName)
        let releaseTokens = tokens(query.releaseName ?? query.fileName)
        let titleTokens = Set(query.titles.flatMap { tokens($0.value) })
        let shared = subtitleTokens.intersection(releaseTokens).subtracting(titleTokens)
        if !shared.isEmpty {
            score += min(50, shared.count * 10)
            reasons.append("Release adı eşleşti")
        }
        let remembered = subtitleTokens.intersection(query.preferredReleaseTokens)
        if !remembered.isEmpty {
            score += min(40, remembered.count * 15)
            reasons.append("Önceki release tercihi")
        }
        switch candidate.language.lowercased() {
        case "tr", "tur", "tr-tr", "turkish":
            score += 70
            reasons.append("Türkçe tercih edildi")
        case "en", "eng", "en-us", "english":
            score += 35
            reasons.append("İngilizce")
        default: break
        }
        if candidate.isMachineTranslated {
            score -= 50
            reasons.append("AI çeviri")
        }
        if candidate.isHearingImpaired {
            score -= 15
            reasons.append("İşitme engelli altyazı")
        }
        if query.isAnime && ["ass", "ssa"].contains(candidate.format?.lowercased() ?? "") {
            score += 5
            reasons.append("Anime ASS biçimi")
        }
        if let downloads = candidate.downloads, downloads > 0 {
            score += min(12, Int(log10(Double(downloads) + 1) * 4))
        }
        if let rating = candidate.rating, rating.isFinite {
            score += min(10, max(0, Int(rating)))
        }
        result.score = score
        result.matchReasons = reasons
        return result
    }

    private static func tokens(_ value: String?) -> Set<String> {
        guard let value else { return [] }
        return Set(SubtitleTitlePolicy.normalized(value).split(separator: " ").map(String.init))
    }
}
