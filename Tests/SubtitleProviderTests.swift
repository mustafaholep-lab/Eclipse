import Foundation
import XCTest
@testable import Eclipse

final class SubtitleProviderTests: XCTestCase {
    func testAutomaticAndManualSubtitleChoicesStaySeparateAcrossEpisodes() {
        var selection = SubtitlePlaybackSelection()
        selection.beginMedia()
        let firstEpisode = selection.generation
        XCTAssertTrue(selection.mayChooseDefault)
        selection.selectAutomatically(preferred: false)
        XCTAssertTrue(selection.mayApplyProviderResult)
        selection.selectAutomatically(preferred: true)
        XCTAssertFalse(selection.mayApplyProviderResult)
        selection.selectByUser()
        selection.selectAutomatically(preferred: false)
        XCTAssertEqual(selection.choice, .user)
        XCTAssertFalse(selection.mayApplyProviderResult)
        selection.beginMedia()
        XCTAssertFalse(selection.acceptsResult(generation: firstEpisode))
        XCTAssertTrue(selection.mayChooseDefault)
    }

    func testManualAnimeSearchPreservesIDsAliasesAndFileExtras() {
        let original = query()
        let edited = SubtitleManualSearch(
            title: "Sorcery Fight", season: 2, episode: 3,
            absoluteEpisode: 27, language: "tr"
        ).applying(to: original)
        XCTAssertEqual(edited.titles.first?.value, "Sorcery Fight")
        XCTAssertTrue(edited.titles.contains { $0.value == "呪術廻戦" })
        XCTAssertEqual(edited.season, 2)
        XCTAssertEqual(edited.episode, 3)
        XCTAssertEqual(edited.animeSeason, 2)
        XCTAssertEqual(edited.animeEpisode, 27)
        XCTAssertEqual(edited.absoluteEpisode, 27)
        XCTAssertEqual(edited.preferredLanguages, ["tr"])
        XCTAssertEqual(edited.ids.anilist, original.ids.anilist)
        XCTAssertEqual(edited.videoHash, original.videoHash)
        XCTAssertEqual(edited.fileSize, original.fileSize)
        let plan = StremioSubtitleRequestPlanner.attempts(
            query: edited, supportedTypes: ["series", "anime"],
            idPrefixes: ["tt", "anilist:"], addonName: "Fixture"
        )
        XCTAssertTrue(plan.contains(.init(type: "series", id: "tt1234567:2:3")))
        XCTAssertTrue(plan.contains(.init(type: "anime", id: "anilist:113415:1:27")))
    }

    func testManualEnglishLanguageControlsRankingAndVisibleResults() {
        let original = query()
        let manual = SubtitleManualSearch(title: "Jujutsu Kaisen", season: 1, episode: 1,
            absoluteEpisode: 1, language: "english").applying(to: original)
        XCTAssertTrue(manual.isManualSearch)
        XCTAssertEqual(manual.preferredLanguages, ["en"])
        for alias in ["en", "eng", "english", "en-us", "EN_US"] {
            XCTAssertEqual(StremioSubtitleLanguagePolicy.canonicalCode(alias), "en")
        }
        for alias in ["tr", "tur", "turkish", "tr-tr"] {
            XCTAssertEqual(StremioSubtitleLanguagePolicy.canonicalCode(alias), "tr")
        }
        let turkish = candidate("Jujutsu.Kaisen.S01E01", language: "tur")
        let english = candidate("Jujutsu.Kaisen.S01E01", language: "eng")
        XCTAssertGreaterThan(SubtitleRanking.score(english, for: manual).score,
                             SubtitleRanking.score(turkish, for: manual).score)
        let visible = SubtitleManualResultPolicy.visible([turkish, english], language: "en") {
            StremioSubtitleLanguagePolicy.canonicalCode($0.language) == $1
        }
        XCTAssertEqual(visible.map(\.language), ["eng"])
        XCTAssertGreaterThan(SubtitleRanking.score(turkish, for: original).score,
                             SubtitleRanking.score(english, for: original).score)
        XCTAssertFalse(original.isManualSearch)
    }

    func testManualStremioEnglishResultsExcludeDeclaredTurkish() throws {
        let response = try JSONDecoder().decode(StremioSubtitleResponse.self, from: Data("""
        {"subtitles":[
          {"id":"tr","lang":"tur","name":"English in release name","url":"https://example.invalid/tr.srt"},
          {"id":"en","lang":"eng","name":"Kaizoku","url":"https://example.invalid/en.srt"}
        ]}
        """.utf8))
        let results = try XCTUnwrap(response.subtitles)
        let visible = SubtitleManualResultPolicy.visible(results, language: "en") { subtitle, language in
            if let declared = StremioSubtitleLanguagePolicy.canonicalCode(subtitle.lang) {
                return declared == language
            }
            return StremioSubtitleLanguagePolicy.matches(subtitle, preferredLanguage: language)
        }
        XCTAssertEqual(visible.map(\.id), ["en"])
    }

    func testSubtitleDelayPreferenceIsReleaseAndEpisodeSpecific() throws {
        let first = try XCTUnwrap(SubtitlePreferenceKey.delay(
            mediaKey: "episode_1_s1_e1", releaseLabel: "SubDL · TR · release A"
        ))
        XCTAssertEqual(first, SubtitlePreferenceKey.delay(
            mediaKey: "episode_1_s1_e1", releaseLabel: "SubDL · TR · release A"
        ))
        XCTAssertNotEqual(first, SubtitlePreferenceKey.delay(
            mediaKey: "episode_1_s1_e1", releaseLabel: "SubDL · TR · release B"
        ))
        XCTAssertNotEqual(first, SubtitlePreferenceKey.delay(
            mediaKey: "episode_1_s1_e2", releaseLabel: "SubDL · TR · release A"
        ))
        XCTAssertNil(SubtitlePreferenceKey.delay(mediaKey: "episode_1_s1_e1", releaseLabel: "  "))
    }

    func testDiagnosticsRedactURLsTokensAndHash() {
        var subtitleQuery = query()
        subtitleQuery.fileName = "https://private.example/u_secret/sub.srt?token=hidden"
        subtitleQuery.videoHash = "1234567890abcdef"
        let report = SubtitleDiagnostics.metadata(subtitleQuery).joined(separator: "\n")
        XCTAssertFalse(report.contains("u_secret"))
        XCTAssertFalse(report.contains("hidden"))
        XCTAssertTrue(report.contains("12345678…"))
        XCTAssertEqual(SubtitleDiagnostics.safeLabel("release?token=hidden"), "[redacted]")
    }

    private struct TimedFixtureProvider: SubtitleProvider {
        let id: String
        let delay: UInt64
        let supportsAnime = true

        func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] {
            try await Task.sleep(nanoseconds: delay)
            return [SubtitleCandidate(
                id: id, providerID: id, language: "tur", releaseName: "S01E01",
                format: "srt", downloads: nil, rating: nil,
                isHearingImpaired: false, isMachineTranslated: false,
                score: 0, matchReasons: []
            )]
        }

        func download(_ candidate: SubtitleCandidate) async throws -> Data { Data() }
    }

    private struct EmptyFixtureProvider: SubtitleProvider {
        let id = "empty-fixture"
        let supportsAnime = true
        func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] { [] }
        func download(_ candidate: SubtitleCandidate) async throws -> Data { Data() }
    }

    private struct FailingFixtureProvider: SubtitleProvider {
        let id = "failing-fixture"
        let supportsAnime = true
        func search(_ query: SubtitleQuery) async throws -> [SubtitleCandidate] {
            throw URLError(.badServerResponse)
        }
        func download(_ candidate: SubtitleCandidate) async throws -> Data { Data() }
    }

    private func query() -> SubtitleQuery {
        SubtitleQuery(
            mediaKind: .anime, isAnime: true,
            ids: SubtitleMediaIDs(imdb: "tt1234567", tmdb: 95479, kitsu: 42765,
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
        XCTAssertEqual(plan.dropFirst().first, .init(type: "anime", id: "anilist:113415:1:1"))
        XCTAssertTrue(plan.contains(.init(type: "anime", id: "anilist:113415:1:1")))
        XCTAssertTrue(plan.contains(.init(type: "series", id: "kitsu:42765:1")))
        XCTAssertTrue(plan.contains(.init(type: "anime", id: "mal:40748:1:1")))
        XCTAssertTrue(plan.contains(.init(type: "series", id: "tt1234567:1:1")))
        XCTAssertLessThan(
            try XCTUnwrap(plan.firstIndex(of: .init(type: "series", id: "tt1234567:1:1"))),
            try XCTUnwrap(plan.firstIndex(of: .init(type: "series", id: "anilist:113415:1")))
        )
        XCTAssertFalse(plan.contains { $0.id.hasPrefix("tmdb:") })
        XCTAssertFalse(plan.contains { $0.type == "anime" && $0.id == "anilist:113415" })
        XCTAssertEqual(query().titles.map(\.value), ["Jujutsu Kaisen", "Sorcery Fight", "呪術廻戦"])
    }

    func testSubtitleComponentIsEnabledByDefaultAndCanBeDisabled() throws {
        let suite = "subtitle-component-fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(StremioAddonComponentSettings.isEnabled(
            sourceID: "stremio:fixture", component: .subtitles, defaults: defaults
        ))
        StremioAddonComponentSettings.setEnabled(
            false, sourceID: "stremio:fixture", component: .subtitles, defaults: defaults
        )
        XCTAssertFalse(StremioAddonComponentSettings.isEnabled(
            sourceID: "stremio:fixture", component: .subtitles, defaults: defaults
        ))
        XCTAssertFalse(SubtitleProviderConfiguration.isEnabled(.subDL, defaults: defaults))
        SubtitleProviderConfiguration.setEnabled(true, provider: .subDL, defaults: defaults)
        XCTAssertTrue(SubtitleProviderConfiguration.isEnabled(.subDL, defaults: defaults))
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

    func testParentSeasonAndAniListLocalEpisodeStaySeparate() {
        var sequel = query()
        sequel.season = 2
        sequel.episode = 3
        sequel.animeSeason = 1
        sequel.animeEpisode = 3
        sequel.absoluteEpisode = 27
        let plan = StremioSubtitleRequestPlanner.attempts(
            query: sequel, supportedTypes: ["series", "anime"],
            idPrefixes: ["tt", "anilist:", "kitsu:"], addonName: "Fixture"
        )
        XCTAssertTrue(plan.contains(.init(type: "series", id: "tt1234567:2:3")))
        XCTAssertTrue(plan.contains(.init(type: "anime", id: "anilist:113415:1:3")))
        XCTAssertTrue(plan.contains(.init(type: "series", id: "kitsu:42765:3")))
        XCTAssertFalse(plan.contains { $0.id == "anilist:113415:2:3"
            || $0.id == "anilist:113415:1:27" })
        let absolute = SubtitleRanking.score(candidate("Jujutsu Kaisen - 27"), for: sequel)
        XCTAssertTrue(absolute.matchReasons.contains("Absolute episode 27 eşleşti"))
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
        XCTAssertTrue(SubtitleRanking.accepts(right))
        XCTAssertFalse(SubtitleRanking.accepts(wrong))
        XCTAssertTrue(SubtitleRanking.accepts(hash))
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
        XCTAssertEqual(release.title, "Title")
        XCTAssertEqual(release.source, "web-dl")
        XCTAssertEqual(SubtitleReleaseName.parse("Title.2160p.x264.2024").absoluteEpisode, nil)
        XCTAssertEqual(SubtitleReleaseName.parse("[Group] Title - 05v2 (1080p).mkv").absoluteEpisode, 5)
        XCTAssertEqual(SubtitleReleaseName.parse("[Group] Title - 05v2 (1080p).mkv").revision, 2)
        XCTAssertEqual(SubtitleReleaseName.parse("Title - 105").absoluteEpisode, 105)
        XCTAssertEqual(SubtitleReleaseName.parse("Title EP05").absoluteEpisode, 5)
    }

    func testTurkishEncodingAndArchiveSelectCorrectEpisode() throws {
        let cue = "1\r\n00:00:01,000 --> 00:00:02,000\r\nğĞşŞıİöÖüÜçÇ\r\n"
        let cp1254 = try XCTUnwrap(cue.data(using: .windowsCP1254))
        let prepared = try SubtitleFileHandling.prepare(cp1254, fileName: "Jujutsu.Kaisen.S01E01.srt")
        XCTAssertEqual(String(data: prepared.data, encoding: .utf8), cue.replacingOccurrences(of: "\r\n", with: "\n"))

        let utf16 = Data([0xff, 0xfe]) + (try XCTUnwrap(cue.data(using: .utf16LittleEndian)))
        let prepared16 = try SubtitleFileHandling.prepare(utf16, fileName: "Jujutsu.Kaisen.S01E01.srt")
        XCTAssertEqual(prepared16.data, prepared.data)

        let zip = try XCTUnwrap(Data(base64Encoded: "UEsDBBQAAAAIAA4lQl3jHfkvHgAAACYAAAAZAAAASnVqdXRzdS5LYWlzZW4uUzAxRTAyLnNydDPkMjCwAiFDHQMDAwVdXTsFqIARSIArvCg/L50LAFBLAwQUAAAACAAOJUJdvQDiaR8AAAAnAAAAGQAAAEp1anV0c3UuS2Fpc2VuLlMwMUUwMS5zcnQz5DIwsAIhQx0DAwMFXV07BaiAEUiAyyX/yPyiUi4AUEsBAhQAFAAAAAgADiVCXeMd+S8eAAAAJgAAABkAAAAAAAAAAAAAAIABAAAAAEp1anV0c3UuS2Fpc2VuLlMwMUUwMi5zcnRQSwECFAAUAAAACAAOJUJdvQDiaR8AAAAnAAAAGQAAAAAAAAAAAAAAgAFVAAAASnVqdXRzdS5LYWlzZW4uUzAxRTAxLnNydFBLBQYAAAAAAgACAI4AAACrAAAAAAA="))
        let selected = try SubtitleFileHandling.prepare(zip, fileName: "season.zip", query: query())
        XCTAssertEqual(selected.fileName, "Jujutsu.Kaisen.S01E01.srt")
        XCTAssertTrue(String(decoding: selected.data, as: UTF8.self).contains("Doğru"))
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(zip, hintedFileName: "subtitle.bin",
            query: query()).format, "srt")

        let gzip = try XCTUnwrap(Data(base64Encoded: "H4sIAIwLv2oC/zPkMjCwAiFDHQMDAwVdXTsFqIARSIAr5PCeouzDy1O5ADDR20gpAAAA"))
        let inflated = try SubtitleFileHandling.prepare(gzip, fileName: "episode.srt.gz")
        XCTAssertTrue(String(decoding: inflated.data, as: UTF8.self).contains("Türkçe"))
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(gzip, hintedFileName: "subtitle.json").format, "srt")

        let ass = Data("[Script Info]\nTitle: Jujutsu Kaisen\n[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,Türkçe\n".utf8)
        XCTAssertEqual(try SubtitleFileHandling.prepare(ass, fileName: "episode.ass").format, "ass")
    }

    func testStremioAIFormatDetectionUsesContentOverMissingOrMisleadingExtension() throws {
        let srt = Data("1\n00:00:01,000 --> 00:00:02,000\nHello\n".utf8)
        let vtt = Data("WEBVTT\n\n00:01.000 --> 00:02.000\nHello\n".utf8)
        let ass = Data("[Script Info]\nTitle: Example\n[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:02.00,Hello\n".utf8)
        let ssa = Data("[Script Info]\nTitle: Example\n[V4 Styles]\nFormat: Name, Fontname\n[Events]\nFormat: Start, End, Text\nDialogue: 0:00:01.00,0:00:02.00,Hello\n".utf8)
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(srt, hintedFileName: "subtitle").format, "srt")
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(vtt, hintedFileName: "subtitle").format, "vtt")
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(ass, hintedFileName: "subtitle").format, "ass")
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(ssa, hintedFileName: "subtitle").format, "ssa")
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(srt, hintedFileName: "subtitle.bin").format, "srt")
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(vtt, hintedFileName: "subtitle.json",
            hintedFormat: "srt").format, "vtt")
        XCTAssertEqual(try SubtitleFileHandling.prepareDetected(ass, hintedFileName: "subtitle.srt").format, "ass")
    }

    func testStremioAIFormatDetectionRejectsMalformedBodyAndPreservesLimit() {
        XCTAssertThrowsError(try SubtitleFileHandling.prepareDetected(Data("garbage".utf8),
            hintedFileName: "subtitle.bin")) { error in
            XCTAssertEqual((error as? SubtitleFileError)?.aiStatus, "Altyazı biçimi tanınamadı")
        }
        XCTAssertThrowsError(try SubtitleFileHandling.prepareDetected(Data("wrong --> timestamps".utf8),
            hintedFileName: "subtitle.srt")) { error in
            XCTAssertEqual((error as? SubtitleFileError)?.aiStatus, "Altyazıda zaman kodu bulunamadı")
        }
        XCTAssertThrowsError(try SubtitleFileHandling.prepareDetected(
            Data(repeating: 0x41, count: SubtitleFileHandling.maximumBytes + 1), hintedFileName: "subtitle.srt")) {
            error in
            XCTAssertEqual((error as? SubtitleFileError)?.aiStatus, "Altyazı 12 MB sınırını aşıyor")
        }
    }

    func testMalformedAndUnsupportedSubtitleFilesFailClearly() {
        XCTAssertThrowsError(try SubtitleFileHandling.prepare(Data(), fileName: "empty.srt"))
        XCTAssertThrowsError(try SubtitleFileHandling.prepare(Data("garbage".utf8), fileName: "bad.srt"))
        XCTAssertThrowsError(try SubtitleFileHandling.prepare(Data("text".utf8), fileName: "bad.exe"))
    }

    func testOpenSubtitlesMovieHashUsesOnlyTheTwoEdgeBlocks() {
        var first = Data(repeating: 0, count: SubtitleMovieHash.blockSize)
        let last = Data(repeating: 0, count: SubtitleMovieHash.blockSize)
        first[0] = 1
        XCTAssertEqual(SubtitleMovieHash.calculate(first: first, last: last, fileSize: 131_072),
                       "0000000000020001")
        XCTAssertNil(SubtitleMovieHash.calculate(first: Data(), last: last, fileSize: 131_072))
        XCTAssertNil(SubtitleMovieHash.calculate(first: first, last: last, fileSize: 100_000))
    }

    func testSubDLOfficialRequestAndRecordedArchiveResponse() throws {
        let provider = SubDLSubtitleProvider(apiKey: "fixture-key")
        let request = try XCTUnwrap(provider.requestURL(query: query(), title: nil))
        let items = try XCTUnwrap(URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "imdb_id" })?.value, "tt1234567")
        XCTAssertEqual(items.first(where: { $0.name == "season_number" })?.value, "1")
        XCTAssertEqual(items.first(where: { $0.name == "episode_number" })?.value, "1")
        XCTAssertEqual(items.first(where: { $0.name == "unpack" })?.value, "1")
        let synonymRequest = try XCTUnwrap(provider.requestURL(query: query(), title: "Sorcery Fight"))
        XCTAssertTrue(synonymRequest.absoluteString.contains("Sorcery%20Fight"))

        let data = Data("""
        {"status":true,"subtitles":[{"release_name":"Season Pack","url":"/subtitle/pack.zip",
          "unpack_files":[
            {"name":"Jujutsu.Kaisen.S01E02.srt","release_name":"S01E02","language":"EN","url":"/subtitle/pack/wrong"},
            {"name":"Jujutsu.Kaisen.S01E01.srt","release_name":"S01E01","language":"TR","format":"srt","url":"/subtitle/pack/right"}
          ]}]}
        """.utf8)
        let results = try provider.decodeCandidates(data, query: query())
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1].language, "TR")
        XCTAssertGreaterThan(results[1].score, results[0].score)
        XCTAssertTrue(results[1].matchReasons.contains("S01E01 eşleşti"))
    }

    func testJimakuUsesAniListAndLocalEpisodeWithoutInventingAbsoluteCoordinate() throws {
        let provider = JimakuSubtitleProvider(apiKey: "fixture-key")
        let urls = provider.searchURLs(query: query())
        XCTAssertTrue(urls.first?.absoluteString.contains("anilist_id=113415") == true)
        XCTAssertTrue(urls.contains {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "tmdb_id" })?.value == "tv:95479"
        })
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("query=Sorcery%20Fight") })
        XCTAssertTrue(provider.filesURL(entryID: 57, episode: query().animeEpisode)?
            .absoluteString.contains("episode=1") == true)

        let fixture = Data("""
        [{"name":"[SubsPlease] Jujutsu Kaisen - 01.ass","size":12345,
          "url":"https://jimaku.cc/api/files/jjk-01.ass"}]
        """.utf8)
        let candidates = try provider.decodeCandidates(fixture, query: query())
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].language, "jpn")
        XCTAssertTrue(candidates[0].matchReasons.contains("Absolute episode 1 eşleşti"))
    }

    func testOpenSubtitlesOfficialRequestAndRecordedSearchResponse() throws {
        let provider = OpenSubtitlesRESTProvider(apiKey: "fixture-key", bearerToken: nil)
        let urls = provider.searchURLs(query: query())
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("moviehash=0123456789abcdef") })
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("parent_imdb_id=1234567") })
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("parent_tmdb_id=95479") })
        XCTAssertTrue(urls.contains { $0.absoluteString.contains("query=Sorcery%20Fight") })
        XCTAssertTrue(urls.allSatisfy { $0.absoluteString.contains("season_number=1")
            && $0.absoluteString.contains("episode_number=1") })

        let fixture = Data("""
        {"data":[{"attributes":{"language":"tr","release":"Jujutsu.Kaisen.S01E01.1080p",
          "download_count":178,"ratings":8.5,"hearing_impaired":false,
          "machine_translated":false,"moviehash_match":true,
          "files":[{"file_id":33221,"file_name":"Jujutsu.Kaisen.S01E01.srt"}]}}]}
        """.utf8)
        let candidates = try provider.decodeCandidates(fixture, query: query())
        XCTAssertEqual(candidates.first?.id, "33221")
        XCTAssertTrue(candidates.first?.matchReasons.contains("Video hash eşleşti") == true)
    }

    @MainActor
    func testFastProviderPublishesBeforeSlowProviderCompletes() async {
        let providers: [any SubtitleProvider] = [
            TimedFixtureProvider(id: "fast-fixture", delay: 20_000_000),
            TimedFixtureProvider(id: "slow-fixture", delay: 500_000_000)
        ]
        var batches: [[SubtitleProviderSearchResult]] = []
        let results = await SubtitleProviderSearchCoordinator.search(
            query: query(), providers: providers
        ) { partial in
            batches.append(partial)
        }
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches.first?.first?.providerID, "fast-fixture")
        XCTAssertEqual(batches.first?.count, 1)
        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testEmptyResponseAndProviderFailureHaveDifferentDiagnostics() async {
        let results = await SubtitleProviderSearchCoordinator.search(
            query: query(), providers: [EmptyFixtureProvider(), FailingFixtureProvider()]
        )
        XCTAssertEqual(results.first(where: { $0.providerID == "empty-fixture" })?.diagnostic,
                       "valid-empty-response")
        XCTAssertEqual(results.first(where: { $0.providerID == "failing-fixture" })?.diagnostic,
                       "request-or-parse-failed")
        XCTAssertEqual(SubtitleProviderSearchResult(
            providerID: "subdl", candidates: [], diagnostic: "valid-empty-response"
        ).sourceLabel, "SubDL")
    }

    @MainActor
    func testEmptyProviderDoesNotHideAnotherProvidersCandidates() async {
        let results = await SubtitleProviderSearchCoordinator.search(
            query: query(), providers: [EmptyFixtureProvider(),
                                       TimedFixtureProvider(id: "matched-fixture", delay: 10_000_000)]
        )
        XCTAssertEqual(results.first(where: { $0.providerID == "empty-fixture" })?.diagnostic,
                       "valid-empty-response")
        XCTAssertEqual(results.flatMap(\.candidates).map(\.providerID), ["matched-fixture"])
    }
}
