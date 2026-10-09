import Foundation
import XCTest
@testable import Eclipse

@MainActor
private final class SyncRendererProbe: EclipseSyncPlayer {
    var media: WatchTogetherMediaDescriptor? = WatchTogetherMediaDescriptor(tmdbID: 603, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
    var position = 10.0
    var playingIntent = true
    var rate = 1.0
    var ready = true
    var buffering = false
    var controls: [String] = []
    var origins: [EclipseSyncCommandOrigin] = []
    var onControl: ((EclipseSyncCommandOrigin) -> Void)?
    var status: EclipseSyncConnectionState = .idle
    var eclipseSyncPlayerSnapshot: EclipseSyncPlaybackSnapshot? {
        media.map { EclipseSyncPlaybackSnapshot(media: $0, position: position, duration: 2_000,
            playing: playingIntent, rate: rate, ready: ready, buffering: buffering) }
    }
    func eclipseSyncSeek(to position: Double, origin: EclipseSyncCommandOrigin) {
        self.position = position; record("seek", origin)
    }
    func eclipseSyncSetRate(_ rate: Double, origin: EclipseSyncCommandOrigin) {
        self.rate = rate; record("rate", origin)
    }
    func eclipseSyncSetPlaying(_ playing: Bool, origin: EclipseSyncCommandOrigin) {
        playingIntent = playing; record(playing ? "play" : "pause", origin)
    }
    func eclipseSyncUpdateStatus(_ state: EclipseSyncConnectionState) { status = state }
    private func record(_ control: String, _ origin: EclipseSyncCommandOrigin) {
        controls.append(control); origins.append(origin); onControl?(origin)
    }
}

@MainActor
final class EclipseSyncPlayerIntegrationTests: XCTestCase {
    private let session = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private var time = 1_000.0

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(predicate(), "Timed out waiting for player integration", file: file, line: line)
    }
    private func drain() async { for _ in 0..<40 { await Task.yield() } }
    private func make(_ player: SyncRendererProbe) -> (EclipseSyncPlayerAdapter, EclipseSyncMockTransport) {
        let wire = EclipseSyncMockTransport()
        wire.onSend = { [weak wire] message in
            if case .ping(let id, let sent) = message {
                wire?.receive(.message(.pong(id: id, clientSentAt: sent, serverReceivedAt: sent, serverSentAt: sent)))
            }
        }
        return (EclipseSyncPlayerAdapter(player: player, transport: wire, automaticTimers: false, now: { self.time }), wire)
    }
    private func state(sequence: UInt64 = 1, position: Double = 100, playing: Bool = true,
                       rate: Double = 1) -> EclipseSyncState {
        let media = WatchTogetherMediaDescriptor(tmdbID: 603, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
        return EclipseSyncState(room: "482731", sessionID: session, media: media,
            mediaId: EclipseSyncState.identifier(for: media)!, playing: playing, position: position, rate: rate,
            sequence: sequence, sentAt: time, stalled: false)
    }
    private func connect(_ adapter: EclipseSyncPlayerAdapter, _ wire: EclipseSyncMockTransport,
                         client: Bool, initial: EclipseSyncState? = nil) async throws {
        try adapter.start(room: client ? "482731" : nil)
        wire.receive(.opened)
        try await waitUntil { wire.sent.contains { message in
            if case .joinRoom = message { return client }
            if case .createRoom = message { return !client }
            return false
        } }
        if client { wire.receive(.message(.joined(room: "482731", sessionID: session, state: initial))) }
        else { wire.receive(.message(.roomCreated(room: "482731", sessionID: session))) }
        try await waitUntil { adapter.coordinator?.sessionID == self.session }
        await drain()
    }

    func testHostPublishesExplicitSeekAndRateBeforeRendererCallbacksThenHeartbeatsLiveState() async throws {
        let player = SyncRendererProbe(); let (adapter, wire) = make(player)
        defer { adapter.cancel() }
        try await connect(adapter, wire, client: false)
        XCTAssertTrue(adapter.permitsLocalControl(.seek))
        adapter.localChange(.seek, position: 125)
        try await waitUntil { adapter.coordinator?.latestState?.reason == .seek }
        XCTAssertEqual(adapter.coordinator?.latestState?.position, 125)
        XCTAssertEqual(player.position, 10) // Renderer has not acknowledged the local seek.
        adapter.localChange(.rate, rate: 1.5)
        XCTAssertEqual(adapter.coordinator?.latestState?.rate, 1.5)
        XCTAssertEqual(adapter.coordinator?.latestState?.position, 125)
        player.position = 126; player.rate = 1.5; player.playingIntent = false
        adapter.localChange(.pause)
        XCTAssertEqual(adapter.coordinator?.latestState?.playing, false)
        player.playingIntent = true; adapter.localChange(.play)
        XCTAssertEqual(adapter.coordinator?.latestState?.playing, true)
        let sequence = adapter.coordinator!.latestState!.sequence
        time += 2; adapter.coordinator?.tick()
        XCTAssertEqual(adapter.coordinator?.latestState?.sequence, sequence + 1)
        XCTAssertEqual(adapter.coordinator?.latestState?.position, 126)
        try await waitUntil { wire.sent.filter { if case .hostState = $0 { return true }; return false }.count == 6 }
    }

    func testRemoteCommandsUseRendererHelpersInOrderAndSuppressSynchronousAndDelayedEcho() async throws {
        let player = SyncRendererProbe(); let (adapter, wire) = make(player)
        defer { adapter.cancel() }
        player.onControl = { [weak adapter] origin in
            adapter?.localChange(.pause) // Synchronous callback has no origin tag.
            adapter?.localChange(.pause, origin: origin)
        }
        try await connect(adapter, wire, client: true, initial: state(playing: false, rate: 1.5))
        XCTAssertEqual(player.controls, ["seek", "rate", "pause"])
        XCTAssertEqual(player.position, 100); XCTAssertEqual(player.rate, 1.5)
        let origin = try XCTUnwrap(player.origins.first)
        guard case .remote = origin else { return XCTFail("Remote origin was lost") }
        XCTAssertTrue(player.origins.allSatisfy { $0 == origin })
        adapter.localChange(.play, origin: origin)
        await drain()
        XCTAssertFalse(wire.sent.contains { if case .hostState = $0 { return true }; return false })
    }

    func testRapidHostSeeksUsePendingTargetAndPausePreservesProjectedPositionUntilAcknowledged() async throws {
        let player = SyncRendererProbe(); let (adapter, wire) = make(player)
        defer { adapter.cancel() }
        try await connect(adapter, wire, client: false)
        adapter.localChange(.seek, position: 100)
        adapter.localChange(.seek, position: try XCTUnwrap(adapter.controlPosition) + 15)
        XCTAssertEqual(adapter.coordinator?.latestState?.position, 115)
        XCTAssertEqual(player.position, 10)
        time += 0.4; player.playingIntent = false
        adapter.localChange(.pause)
        XCTAssertEqual(try XCTUnwrap(adapter.coordinator?.latestState?.position), 115.4, accuracy: 0.001)
        adapter.localChange(.rate, rate: 1.5)
        XCTAssertEqual(try XCTUnwrap(adapter.coordinator?.latestState?.position), 115.4, accuracy: 0.001)
        time += 0.2
        XCTAssertEqual(try XCTUnwrap(adapter.controlPosition), 115.4, accuracy: 0.001)
        player.position = 115.4
        XCTAssertEqual(try XCTUnwrap(adapter.controlPosition), 115.4, accuracy: 0.001)
        player.position = 116
        XCTAssertEqual(adapter.controlPosition, 116)
    }

    func testClientControlsRemainRejectedWhileBufferingAndReconnectResyncsOnce() async throws {
        let player = SyncRendererProbe(); player.buffering = true
        let (adapter, wire) = make(player)
        defer { adapter.cancel() }
        try await connect(adapter, wire, client: true, initial: state())
        XCTAssertFalse(adapter.permitsLocalControl(.seek))
        XCTAssertTrue(player.controls.isEmpty)
        wire.receive(.message(.state(state(sequence: 2, position: 130, playing: false))))
        try await waitUntil { adapter.coordinator?.latestState?.sequence == 2 }
        player.buffering = false; adapter.readinessChanged()
        XCTAssertEqual(player.controls, ["seek", "pause"])
        XCTAssertEqual(player.position, 130); XCTAssertFalse(player.playingIntent)
        wire.receive(.closed(.connection))
        try await waitUntil { adapter.state == .reconnecting(attempt: 1) }
        XCTAssertFalse(adapter.permitsLocalControl(.play))
        adapter.coordinator?.reconnectNow(); wire.receive(.opened)
        try await waitUntil { wire.sent.filter { if case .joinRoom = $0 { return true }; return false }.count == 2 }
        wire.receive(.message(.joined(room: "482731", sessionID: session, state: state(sequence: 2, position: 130, playing: false))))
        try await waitUntil { player.controls.count == 4 }
        wire.receive(.message(.state(state(sequence: 2, position: 500))))
        await drain()
        XCTAssertEqual(player.controls.count, 4); XCTAssertEqual(player.position, 130)
    }

    func testInvalidJoinDoesNotAcquirePlaybackOrDisconnectAnExistingMode() {
        let player = SyncRendererProbe(); let (adapter, wire) = make(player)
        defer { adapter.cancel() }
        var acquired = false
        adapter.onAcquirePlayback = { acquired = true }
        XCTAssertThrowsError(try adapter.start(room: "12345"))
        XCTAssertFalse(acquired); XCTAssertEqual(wire.connectionCount, 0)
        player.media = nil
        XCTAssertThrowsError(try adapter.start())
        XCTAssertFalse(acquired); XCTAssertNil(EclipseSyncPlayerAdapter.active)
    }

    func testOnlyOnePlayerCanAcquireSyncAndLeavingReleasesOwnership() async throws {
        let first = SyncRendererProbe(); let second = SyncRendererProbe()
        let (adapter, wire) = make(first); let (other, otherWire) = make(second)
        defer { adapter.cancel(); other.cancel() }
        var modeSwitches = 0
        adapter.onAcquirePlayback = { modeSwitches += 1 }
        try await connect(adapter, wire, client: false)
        XCTAssertEqual(modeSwitches, 1)
        XCTAssertTrue(EclipseSyncPlayerAdapter.active === adapter)
#if os(iOS)
        let sharePlay = await WatchTogetherCoordinator.shared.beginActivity()
        guard case .unavailable(let reason) = sharePlay else { return XCTFail("SharePlay acquired active Sync playback") }
        XCTAssertEqual(reason, "Leave Eclipse Sync before starting Apple SharePlay.")
#endif
        XCTAssertThrowsError(try other.start())
        XCTAssertEqual(otherWire.connectionCount, 0)
        await adapter.leave()
        XCTAssertTrue(wire.sent.contains { if case .leaveRoom = $0 { return true }; return false })
        XCTAssertFalse(wire.isConnected); XCTAssertNil(EclipseSyncPlayerAdapter.active)
        try other.start()
        XCTAssertTrue(EclipseSyncPlayerAdapter.active === other)
    }

    func testMismatchAndServerErrorsReleasePlaybackWithoutChangingMedia() async throws {
        let player = SyncRendererProbe(); let (adapter, wire) = make(player)
        defer { adapter.cancel() }
        try await connect(adapter, wire, client: true)
        wire.receive(.message(.error(.mediaMismatch)))
        try await waitUntil { adapter.state == .mismatch }
        XCTAssertTrue(player.controls.isEmpty); XCTAssertEqual(player.media?.tmdbID, 603)
        XCTAssertNil(EclipseSyncPlayerAdapter.active)
        let (second, secondWire) = make(player)
        defer { second.cancel() }
        try await connect(second, secondWire, client: true)
        secondWire.receive(.message(.error(.roomFull)))
        try await waitUntil { second.state == .rejected(.roomFull) }
        XCTAssertEqual(second.statusText, "The room already has a client.")
        XCTAssertFalse(secondWire.isConnected); XCTAssertNil(EclipseSyncPlayerAdapter.active)
    }

    func testPlayerTeardownCancelsPendingBufferStateAndLateMessages() async throws {
        let player = SyncRendererProbe(); player.ready = false
        let (adapter, wire) = make(player)
        try await connect(adapter, wire, client: true, initial: state())
        adapter.cancel()
        player.ready = true; adapter.readinessChanged()
        wire.receive(.message(.state(state(sequence: 2))))
        time += 30; adapter.coordinator?.tick(); await drain()
        XCTAssertTrue(player.controls.isEmpty)
        XCTAssertFalse(wire.isConnected); XCTAssertNil(EclipseSyncPlayerAdapter.active)
    }
}
