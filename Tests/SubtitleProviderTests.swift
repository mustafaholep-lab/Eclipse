import Foundation
import XCTest
@testable import Eclipse

final class SubtitleProviderTests: XCTestCase {
    private func query() -> SubtitleQuery {
        SubtitleQuery(
            mediaKind: .anime, isAnime: true,
            ids: SubtitleMediaIDs(imdb: "tt1234567", tmdb: 95479, kitsu: 42309,
                                  anilist: 113415, mal: 40748),
            season: 1, episode: 1, animeSeason: 1, animeEpisode: 1,
            absoluteEpisode: 1, year: 2020,
            titles: SubtitleTitlePolicy.variants([
                ("Jujutsu Kaisen", .displayed),
                ("Sorcery Fight", .synonym),
                ("呪術廻戦", .native)
            ]),
            fileName: "[SubsPlease] Jujutsu Kaisen - 01 (1080p).mkv",
            releaseName: "[SubsPlease] Jujutsu Kaisen - 01 (1080p).mkv",
            videoHash: "0123456789abcdef", fileSize: 1_234_567_890,
            duration: 1_440
        )
    }

    func testAnimeSubManifestAndComponentCompatiblePlan() throws {
        let manifest = try JSONDecoder().decode(StremioManifest.self, from: Data("""
        {"id":"org.soluserv.animesub","name":"AnimeSub+",
         "types":["anime","movie","series"],
         "resources":[
           {"name":"stream","types":["anime","movie","series"],"idPrefixes":["anilist:","kitsu:","mal:","tt"]},
           {"name":"subtitles","types":["anime","movie","series"],"idPrefixes":["anilist:","kitsu:","mal:","tt"]}
         ]}
        """.utf8))
        XCTAssertTrue(manifest.supportsSubtitles)
        XCTAssertTrue(manifest.supportsResource("subtitles", type: "series"))
        XCTAssertTrue(manifest.supportsResource("subtitles", type: "anime"))

        let supported = ["movie", "series", "anime"].filter {
            manifest.supportsResource("subtitles", type: $0)
        }
        let plan = StremioSubtitleRequestPlanner.attempts(
            query: query(), supportedTypes: supported,
            idPrefixes: manifest.subtitleIdPrefixes, addonName: manifest.name
        )
        XCTAssertEqual(plan.first, .init(type: "series", id: "anilist:113415:1:1"))
        XCTAssertTrue(plan.contains(.init(type: "anime", id: "anilist:113415:1:1")))
        XCTAssertTrue(plan.contains(.init(type: "series", id: "kitsu:42309:1")))
        XCTAssertTrue(plan.contains(.init(type: "anime", id: "mal:40748:1:1")))
        XCTAssertTrue(plan.contains(.init(type: "series", id: "tt1234567:1:1")))
        XCTAssertFalse(plan.contains { $0.id.hasPrefix("tmdb:") })
        XCTAssertFalse(plan.contains { $0.type == "anime" && $0.id == "anilist:113415" })
        XCTAssertEqual(query().titles.map(\.value), ["Jujutsu Kaisen", "Sorcery Fight", "呪術廻戦"])
    }

    func testStremioURLPreservesFileExtrasAndEpisodeID() throws {
        let url = try XCTUnwrap(StremioClient.shared.subtitleRequestURL(
            baseURL: "https://example.org/user-key",
            type: "anime", id: "anilist:113415:1:1",
            videoHash: "0123456789abcdef", videoSize: 1_234_567_890,
            filename: "Jujutsu Kaisen - 01 [TR].mkv"
        ))
        let path = url.absoluteString
        XCTAssertTrue(path.contains("/subtitles/anime/anilist:113415:1:1/"))
        XCTAssertTrue(path.contains("videoHash=0123456789abcdef"))
        XCTAssertTrue(path.contains("videoSize=1234567890"))
        XCTAssertTrue(path.contains("filename=Jujutsu%20Kaisen%20-%2001%20%5BTR%5D.mkv"))
    }

    func testRecordedSubtitleJSONKeepsLabelLanguageAndURL() throws {
        let response = try JSONDecoder().decode(StremioSubtitleResponse.self, from: Data("""
        {"subtitles":[{"id":"tr-1","lang":"tur","label":"JJK S01E01 Türkçe",
                       "url":"https://example.org/subtitles/jjk-1.srt"}]}
        """.utf8))
        let subtitle = try XCTUnwrap(response.subtitles?.first)
        XCTAssertEqual(subtitle.lang, "tur")
        XCTAssertEqual(subtitle.name, "JJK S01E01 Türkçe")
        XCTAssertEqual(subtitle.url, "https://example.org/subtitles/jjk-1.srt")
    }

    private func candidate(_ name: String, language: String = "tur",
                           hash: String? = nil, translated: Bool = false,
                           hearingImpaired: Bool = false) -> SubtitleCandidate {
        SubtitleCandidate(
            id: name, providerID: "fixture", language: language,
            releaseName: name, format: "ass", downloads: nil, rating: nil,
            isHearingImpaired: hearingImpaired, isMachineTranslated: translated,
            score: 0, matchReasons: [], videoHash: hash
        )
    }

    func testRankingRejectsWrongEpisodeAndRewardsExactHash() {
        let right = SubtitleRanking.score(candidate("[SubsPlease] Jujutsu Kaisen - 01 1080p WEB-DL"), for: query())
        let wrong = SubtitleRanking.score(candidate("Jujutsu.Kaisen.S01E02.1080p.WEB-DL"), for: query())
        let hash = SubtitleRanking.score(candidate("Jujutsu.Kaisen.S01E02", hash: "0123456789abcdef"), for: query())
        XCTAssertGreaterThan(right.score, wrong.score)
        XCTAssertGreaterThan(hash.score, right.score)
        XCTAssertTrue(right.matchReasons.contains("Absolute episode 1 eşleşti"))
        XCTAssertTrue(wrong.matchReasons.contains("Farklı sezon/bölüm"))
        XCTAssertTrue(hash.matchReasons.contains("Video hash eşleşti"))
    }

    func testRankingPrefersHumanTurkishAndPenalizesTranslationAndHI() {
        let turkish = SubtitleRanking.score(candidate("Jujutsu.Kaisen.S01E01", language: "tur"), for: query())
        let english = SubtitleRanking.score(candidate("Jujutsu.Kaisen.S01E01", language: "eng"), for: query())
        let translated = SubtitleRanking.score(candidate("Jujutsu.Kaisen.S01E01", translated: true), for: query())
        let hi = SubtitleRanking.score(candidate("Jujutsu.Kaisen.S01E01", hearingImpaired: true), for: query())
        XCTAssertGreaterThan(turkish.score, english.score)
        XCTAssertGreaterThan(english.score, translated.score)
        XCTAssertGreaterThan(turkish.score, hi.score)
    }

    func testReleaseParserDoesNotTreatTechnicalNumbersAsEpisodes() {
        let release = SubtitleReleaseName.parse("Title.S02E05.1080p.WEB-DL.x265.10bit")
        XCTAssertEqual(release.season, 2)
        XCTAssertEqual(release.episode, 5)
        XCTAssertEqual(release.source, "web-dl")
        XCTAssertEqual(SubtitleReleaseName.parse("Title.2160p.x264.2024").absoluteEpisode, nil)
        XCTAssertEqual(SubtitleReleaseName.parse("[Group] Title - 05v2 (1080p).mkv").absoluteEpisode, 5)
        XCTAssertEqual(SubtitleReleaseName.parse("Title EP05").absoluteEpisode, 5)
    }
}
