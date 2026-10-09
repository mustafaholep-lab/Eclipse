import Foundation
import XCTest
@testable import Eclipse

final class EclipseSyncProtocolTests: XCTestCase {
    private let session = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private var movie: WatchTogetherMediaDescriptor {
        WatchTogetherMediaDescriptor(tmdbID: 603, mediaType: "movie", seasonNumber: nil, episodeNumber: nil, title: "The Matrix")
    }
    private func state(playing: Bool = true, rate: Double = 1, stalled: Bool = false) -> EclipseSyncState {
        EclipseSyncState(room: "482731", sessionID: session, media: movie,
                         mediaId: EclipseSyncState.identifier(for: movie)!, playing: playing,
                         position: 100, rate: rate, sequence: 1, sentAt: 1_000, stalled: stalled)
    }

    func testAllMessagesRoundTripWithProtocolVersion() throws {
        let id = UUID()
        let messages: [EclipseSyncMessage] = [
            .createRoom(media: movie), .joinRoom(room: "482731", media: movie),
            .leaveRoom(room: "482731", sessionID: session), .hostState(state()), .ping(id: id, sentAt: 1_000),
            .roomCreated(room: "482731", sessionID: session), .joined(room: "482731", sessionID: session, state: state()),
            .joined(room: "482731", sessionID: session, state: nil),
            .participantJoined(room: "482731", sessionID: session), .participantLeft(room: "482731", sessionID: session),
            .state(state()), .roomClosed(room: "482731", sessionID: session, reason: .hostLeft), .error(.mediaMismatch),
            .pong(id: id, clientSentAt: 1_000, serverReceivedAt: 1_001, serverSentAt: 1_001)
        ]
        for message in messages {
            let data = try message.encoded()
            XCTAssertEqual(try EclipseSyncMessage.decode(data), message)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["protocolVersion"] as? Int, 1)
        }
    }

    func testUnknownOrMissingProtocolVersionIsRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: EclipseSyncMessage.createRoom(media: movie).encoded()) as? [String: Any])
        object["protocolVersion"] = 2
        XCTAssertThrowsError(try EclipseSyncMessage.decode(JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? EclipseSyncProtocolError, .unsupportedVersion)
        }
        object.removeValue(forKey: "protocolVersion")
        XCTAssertThrowsError(try EclipseSyncMessage.decode(JSONSerialization.data(withJSONObject: object)))
    }

    func testUnknownFieldsCannotCarrySecretsAtAnyLevel() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: EclipseSyncMessage.state(state()).encoded()) as? [String: Any])
        for field in ["streamURL", "headers", "apiKey", "cookies", "subtitleURL", "authToken"] {
            var root = original
            root[field] = "secret"
            XCTAssertThrowsError(try EclipseSyncMessage.decode(JSONSerialization.data(withJSONObject: root)))
            var payload = try XCTUnwrap(original["state"] as? [String: Any])
            payload[field] = "secret"
            root = original; root["state"] = payload
            XCTAssertThrowsError(try EclipseSyncMessage.decode(JSONSerialization.data(withJSONObject: root)))
            var media = try XCTUnwrap(payload["media"] as? [String: Any])
            media[field] = "secret"
            payload = try XCTUnwrap(original["state"] as? [String: Any]); payload["media"] = media
            root = original; root["state"] = payload
            XCTAssertThrowsError(try EclipseSyncMessage.decode(JSONSerialization.data(withJSONObject: root)))
        }
    }

    func testOversizedAndInvalidStatesFailClosed() throws {
        XCTAssertThrowsError(try EclipseSyncMessage.decode(Data(repeating: 0x20, count: EclipseSyncMessage.maximumBytes + 1)))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: EclipseSyncMessage.state(state()).encoded()) as? [String: Any])
        let original = try XCTUnwrap(root["state"] as? [String: Any])
        for (key, value) in [("position", -1 as Any), ("rate", 0 as Any), ("sequence", 0 as Any), ("mediaId", "wrong" as Any), ("room", "12345" as Any)] {
            var payload = original; payload[key] = value; root["state"] = payload
            XCTAssertThrowsError(try EclipseSyncMessage.decode(JSONSerialization.data(withJSONObject: root)))
        }
    }

    func testLogicalIdentityDoesNotDependOnTitleOrStream() {
        let differentTitle = WatchTogetherMediaDescriptor(tmdbID: 603, mediaType: "movie", seasonNumber: nil, episodeNumber: nil, title: "Matrix")
        XCTAssertTrue(movie.isSameLogicalMedia(as: differentTitle))
        XCTAssertEqual(EclipseSyncState.identifier(for: movie), EclipseSyncState.identifier(for: differentTitle))
        let otherMovie = WatchTogetherMediaDescriptor(tmdbID: 604, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
        XCTAssertFalse(movie.isSameLogicalMedia(as: otherMovie))
        let first = WatchTogetherMediaDescriptor(tmdbID: 100, mediaType: "tv", seasonNumber: 1, episodeNumber: 2)
        let next = WatchTogetherMediaDescriptor(tmdbID: 100, mediaType: "tv", seasonNumber: 1, episodeNumber: 3)
        XCTAssertFalse(first.isSameLogicalMedia(as: next))
    }

    func testAnimeMatchingUsesExistingCanonicalPolicy() throws {
        func descriptor(rawID: Int, canonicalID: Int, episode: Int) -> WatchTogetherMediaDescriptor {
            let context = EpisodePlaybackContext(localSeasonNumber: 2, localEpisodeNumber: episode,
                anilistMediaId: rawID, canonicalAniListMediaId: canonicalID, malMediaId: 51_009, kitsuMediaId: nil,
                tmdbSeasonNumber: 1, tmdbEpisodeNumber: 24 + episode, tmdbEpisodeOffset: 24,
                animeAbsoluteEpisodeNumber: 24 + episode, animeSeasonEpisodeCount: 23, isSpecial: false, titleOnlySearch: false)
            return WatchTogetherMediaDescriptor(tmdbID: 95_479, mediaType: "tv", seasonNumber: 1,
                                               episodeNumber: 24 + episode, playbackContext: context, isAnime: true)
        }
        let first = descriptor(rawID: 145_064, canonicalID: 145_064, episode: 5)
        let alias = descriptor(rawID: 999, canonicalID: 145_064, episode: 5)
        XCTAssertTrue(first.isSameLogicalMedia(as: alias))
        XCTAssertFalse(first.isSameLogicalMedia(as: descriptor(rawID: 145_064, canonicalID: 145_064, episode: 6)))
        XCTAssertEqual(try EclipseSyncMessage.decode(EclipseSyncMessage.createRoom(media: first).encoded()), .createRoom(media: first))
    }

    func testDelayedHeartbeatUsesRateAndDoesNotAdvancePausedOrStalledHost() {
        XCTAssertEqual(state().projectedPosition(at: 1_000.8), 100.8, accuracy: 0.001)
        XCTAssertEqual(state(rate: 2).projectedPosition(at: 1_000.8), 101.6, accuracy: 0.001)
        XCTAssertEqual(state(playing: false).projectedPosition(at: 1_000.8), 100)
        XCTAssertEqual(state(stalled: true).projectedPosition(at: 1_000.8), 100)
        XCTAssertEqual(state().projectedPosition(at: 999), 100)
        XCTAssertEqual(state().projectedPosition(at: 1_005, duration: 103), 102)
    }

    func testDriftBandsAndForcedResync() {
        XCTAssertFalse(EclipseSyncDriftPolicy.shouldSeek(local: 100, target: 100.49, force: false))
        XCTAssertFalse(EclipseSyncDriftPolicy.shouldSeek(local: 100, target: 101, force: false))
        XCTAssertFalse(EclipseSyncDriftPolicy.shouldSeek(local: 100, target: 101.5, force: false))
        XCTAssertTrue(EclipseSyncDriftPolicy.shouldSeek(local: 100, target: 101.51, force: false))
        XCTAssertTrue(EclipseSyncDriftPolicy.shouldSeek(local: 100, target: 100, force: true))
    }

    func testPingPongEstimatesClockOffsetAndRejectsBadSamples() {
        var clock = EclipseSyncClock()
        XCTAssertTrue(clock.record(clientSent: 1_000, serverReceived: 1_003.1, serverSent: 1_003.1, clientReceived: 1_000.2))
        XCTAssertEqual(clock.offset!, 3, accuracy: 0.0001)
        XCTAssertFalse(clock.record(clientSent: 1_000, serverReceived: 1_003, serverSent: 1_004, clientReceived: 1_000.2))
        XCTAssertEqual(clock.offset!, 3, accuracy: 0.0001)
    }
}
