import XCTest
@testable import Eclipse

final class SubtitleMetadataResolverTests: XCTestCase {
    func testTitleVariantsPreserveMeaningfulNumbersAndDeduplicateAliases() {
        XCTAssertEqual(SubtitleTitlePolicy.baseTitle("Jujutsu Kaisen 2nd Season"), "Jujutsu Kaisen")
        XCTAssertEqual(SubtitleTitlePolicy.baseTitle("Jujutsu Kaisen Season 2 (TV)"), "Jujutsu Kaisen")
        XCTAssertEqual(SubtitleTitlePolicy.baseTitle("Jujutsu Kaisen Part II"), "Jujutsu Kaisen")
        XCTAssertNil(SubtitleTitlePolicy.baseTitle("86"))
        XCTAssertNil(SubtitleTitlePolicy.baseTitle("3-gatsu no Lion"))
        XCTAssertEqual(SubtitleTitlePolicy.normalized("Şōwa   Gènroku!"), "sowa genroku")

        let input: [(String, SubtitleTitleVariant.Origin)] = [
            ("Jujutsu Kaisen", .displayed),
            ("jujutsu-káisen", .romaji),
            ("呪術廻戦", .native),
            ("Sorcery Fight", .english),
            ("Sorcery Fight", .synonym)
        ]
        let variants = SubtitleTitlePolicy.variants(input)
        XCTAssertEqual(variants.map(\.value), ["Jujutsu Kaisen", "呪術廻戦", "Sorcery Fight"])
        XCTAssertEqual(variants.map(\.origin), [.displayed, .native, .english])
        XCTAssertEqual(SubtitleTitlePolicy.variants(input, limit: 2).count, 2)
    }

    func testKnownAbsoluteCoordinateMapsBothDirectionsWithoutGuessingAnotherCour() {
        let context = EpisodePlaybackContext(
            localSeasonNumber: 4, localEpisodeNumber: 12,
            anilistMediaId: 123, tmdbSeasonNumber: 4, tmdbEpisodeNumber: 12,
            tmdbEpisodeOffset: 0, animeAbsoluteEpisodeNumber: 87,
            animeSeasonEpisodeCount: 13, isSpecial: false, titleOnlySearch: false
        )
        let mapping = try! XCTUnwrap(SubtitleEpisodeMapping(context: context))
        XCTAssertEqual(mapping.absolute(season: 4, episode: 12), 87)
        XCTAssertEqual(mapping.absolute(season: 4, episode: 13), 88)
        XCTAssertEqual(mapping.coordinate(absolute: 76)?.episode, 1)
        XCTAssertEqual(mapping.coordinate(absolute: 88)?.season, 4)
        XCTAssertNil(mapping.absolute(season: 3, episode: 12))
        XCTAssertNil(mapping.absolute(season: 4, episode: 14))
        XCTAssertNil(mapping.coordinate(absolute: 89))

        let unknownCourLength = EpisodePlaybackContext(
            localSeasonNumber: 2, localEpisodeNumber: 1,
            anilistMediaId: 456, tmdbSeasonNumber: nil, tmdbEpisodeNumber: nil,
            tmdbEpisodeOffset: nil, animeAbsoluteEpisodeNumber: 13,
            animeSeasonEpisodeCount: nil, isSpecial: false, titleOnlySearch: true
        )
        let partial = try! XCTUnwrap(SubtitleEpisodeMapping(context: unknownCourLength))
        XCTAssertEqual(partial.absolute(season: 2, episode: 1), 13)
        XCTAssertNil(partial.absolute(season: 2, episode: 2))
        XCTAssertNil(partial.coordinate(absolute: 14))
    }

    func testEpisodeVariantsAreStructuredAndDeduplicated() {
        XCTAssertEqual(
            SubtitleEpisodeQueryPolicy.variants(season: 4, episode: 12, absoluteEpisode: 87),
            ["S04E12", "12", "EP12", "E12", "Episode 12", "87"]
        )
        XCTAssertEqual(SubtitleEpisodeQueryPolicy.variants(season: nil, episode: 1, absoluteEpisode: 1),
                       ["1", "EP1", "E1", "Episode 1"])
    }

    func testStableCacheKeysPreferAniListAndDoNotIncludeEpisode() {
        let ids = SubtitleMediaIDs(imdb: "tt12343534", tmdb: 95479, kitsu: 42765,
                                   anilist: 113415, mal: 40748, tvdb: 377543, anidb: 15275)
        XCTAssertEqual(ids.seriesCacheKey, "anilist:113415")
        XCTAssertEqual(SubtitleMediaIDs(imdb: "TT12343534", tmdb: 95479).seriesCacheKey,
                       "imdb:tt12343534")
        XCTAssertEqual(SubtitleMediaIDs(tmdb: 95479).seriesCacheKey, "tmdb:95479")
    }

    @MainActor
    func testResolverKeepsAnimeSubSeriesCoordinatesAndEnrichesAliases() async {
        let context = EpisodePlaybackContext(
            localSeasonNumber: 1, localEpisodeNumber: 1, anilistMediaId: 113415,
            malMediaId: 40748, kitsuMediaId: nil, tmdbSeasonNumber: 1,
            tmdbEpisodeNumber: 1, tmdbEpisodeOffset: 0,
            animeAbsoluteEpisodeNumber: 1, animeSeasonEpisodeCount: 24,
            isSpecial: false, titleOnlySearch: false
        )
        let fingerprint = PlaybackStreamFingerprint(
            filename: "[Group] Jujutsu Kaisen - 01.mkv", videoHash: "0123456789abcdef",
            infoHash: "torrent-hash-is-not-video-hash", videoSize: 345_678_901,
            bingeGroup: nil, labels: ["Group WEB-DL"]
        )
        let launch = PlaybackLaunchContext(
            sourceId: "anime-sub-fixture", sourceName: "AnimeSub+", sourceKind: .stremio,
            autoMode: false, streamURL: "https://example.invalid/video.mkv", headers: [:],
            subtitles: [], subtitleNames: nil, retryCount: 0,
            titleCandidates: ["Jujutsu Kaisen"], streamFingerprint: fingerprint
        )
        let request = PlaybackRequest(
            url: URL(string: "https://example.invalid/video.mkv")!,
            mediaInfo: .episode(showId: 95479, seasonNumber: 1, episodeNumber: 1,
                                showTitle: "Jujutsu Kaisen", isAnime: true),
            mediaYear: 2020, imdbID: "tt12343534", episodePlaybackContext: context,
            launchContext: launch, title: "Jujutsu Kaisen", isAnime: true
        )
        let resolver = SubtitleMetadataResolver(identityLoader: { _ in
            SubtitleAnimeIdentity(anilist: 113415, mal: 40748, kitsu: 42765,
                                  romaji: "Jujutsu Kaisen", english: "Sorcery Fight",
                                  native: "呪術廻戦", synonyms: ["JJK"])
        })
        let query = await resolver.resolve(request: request, duration: 1_440)
        XCTAssertEqual(query.mediaKind, .anime)
        XCTAssertEqual(query.mediaKind.stremioTypes, ["series", "anime"])
        XCTAssertEqual(query.ids.tmdb, 95479)
        XCTAssertEqual(query.ids.kitsu, 42765)
        XCTAssertEqual(query.ids.anilist, 113415)
        XCTAssertEqual(query.ids.mal, 40748)
        XCTAssertEqual(query.season, 1)
        XCTAssertEqual(query.episode, 1)
        XCTAssertEqual(query.animeSeason, 1)
        XCTAssertEqual(query.animeEpisode, 1)
        XCTAssertEqual(query.absoluteEpisode, 1)
        XCTAssertEqual(query.year, 2020)
        XCTAssertEqual(query.preferredLanguages, ["tr", "en"])
        XCTAssertEqual(query.videoHash, "0123456789abcdef")
        XCTAssertEqual(query.fileSize, 345_678_901)
        XCTAssertEqual(query.duration, 1_440)
        XCTAssertTrue(query.titles.contains { $0.value == "Sorcery Fight" })
        XCTAssertTrue(query.titles.contains { $0.value == "呪術廻戦" })
        XCTAssertTrue(query.titles.contains { $0.value == "JJK" })
    }

    @MainActor
    func testResolverKeepsMovieResourceTypeForAnimeMovie() async {
        let request = PlaybackRequest(
            url: URL(string: "https://example.invalid/movie.mkv")!,
            mediaInfo: .movie(id: 810693, title: "Jujutsu Kaisen 0", isAnime: true),
            title: "Jujutsu Kaisen 0", isAnime: true
        )
        let query = await SubtitleMetadataResolver().resolve(request: request)
        XCTAssertEqual(query.mediaKind, .movie)
        XCTAssertTrue(query.isAnime)
        XCTAssertEqual(query.mediaKind.stremioTypes, ["movie"])
        XCTAssertEqual(query.titles.first?.value, "Jujutsu Kaisen 0")
    }

    func testCacheCoalescesSuccessfulLookupAndRetriesMissingIdentity() async {
        actor Counter {
            var count = 0
            func next() -> Int { count += 1; return count }
            func value() -> Int { count }
        }
        let counter = Counter()
        let cache = SubtitleMetadataCache()
        let load: @Sendable () async -> SubtitleAnimeIdentity? = {
            _ = await counter.next()
            try? await Task.sleep(nanoseconds: 30_000_000)
            return SubtitleAnimeIdentity(anilist: 113415, mal: 40748, kitsu: nil,
                                         romaji: nil, english: nil, native: nil, synonyms: [])
        }
        async let first = cache.value(for: "anilist:113415", load: load)
        async let second = cache.value(for: "anilist:113415", load: load)
        _ = await (first, second)
        let afterCoalescing = await counter.value()
        XCTAssertEqual(afterCoalescing, 1)
        _ = await cache.value(for: "anilist:113415", load: load)
        let afterCacheHit = await counter.value()
        XCTAssertEqual(afterCacheHit, 1)
        _ = await cache.value(for: "anilist:999", load: { nil })
        _ = await cache.value(for: "anilist:999", load: load)
        let afterMiss = await counter.value()
        XCTAssertEqual(afterMiss, 2)
    }
}
