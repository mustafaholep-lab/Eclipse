import Foundation
import XCTest
@testable import Eclipse

@MainActor
private final class SyncPlaybackProbe: EclipseSyncPlaybackDelegate {
    var media = WatchTogetherMediaDescriptor(tmdbID: 603, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
    var position = 0.0
    var playing = true
    var rate = 1.0
    var ready = true
    var buffering = false
    var commands: [EclipseSyncPlaybackCommand] = []
    var states: [EclipseSyncConnectionState] = []
    var onApply: ((EclipseSyncPlaybackCommand) -> Void)?
    var eclipseSyncSnapshot: EclipseSyncPlaybackSnapshot {
        EclipseSyncPlaybackSnapshot(media: media, position: position, duration: 2_000,
                                   playing: playing, rate: rate, ready: ready, buffering: buffering)
    }
    func eclipseSyncApply(_ command: EclipseSyncPlaybackCommand) {
        commands.append(command)
        if command.shouldSeek { position = command.position }
        playing = command.playing; rate = command.rate
        onApply?(command)
    }
    func eclipseSyncConnectionChanged(_ state: EclipseSyncConnectionState) { states.append(state) }
}

@MainActor
final class EclipseSyncCoordinatorTests: XCTestCase {
    private let session = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
    private var time = 1_000.0
    private func state(sequence: UInt64 = 1, position: Double = 100, playing: Bool = true,
                       reason: EclipseSyncStateReason = .heartbeat, media: WatchTogetherMediaDescriptor? = nil,
                       sentAt: Double = 1_003) -> EclipseSyncState {
        let media = media ?? WatchTogetherMediaDescriptor(tmdbID: 603, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
        return EclipseSyncState(room: "482731", sessionID: session, media: media,
            mediaId: EclipseSyncState.identifier(for: media)!, playing: playing, position: position,
            rate: 1, sequence: sequence, sentAt: sentAt, stalled: false, reason: reason)
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(predicate(), "Timed out waiting for transport/coordinator", file: file, line: line)
    }
    private func drain() async { for _ in 0..<40 { await Task.yield() } }
    private func make(_ probe: SyncPlaybackProbe) -> (EclipseSyncCoordinator, EclipseSyncMockTransport) {
        let transport = EclipseSyncMockTransport()
        transport.onSend = { [weak transport] message in
            if case .ping(let id, let time) = message {
                transport?.receive(.message(.pong(id: id, clientSentAt: time, serverReceivedAt: time + 3, serverSentAt: time + 3)))
            }
        }
        let coordinator = EclipseSyncCoordinator(transport: transport, playback: probe, automaticTimers: false, now: { self.time })
        return (coordinator, transport)
    }
    private func join(_ coordinator: EclipseSyncCoordinator, _ transport: EclipseSyncMockTransport,
                      initial: EclipseSyncState? = nil) async throws {
        try coordinator.joinRoom("482731")
        transport.receive(.opened)
        try await waitUntil { transport.sent.contains { if case .joinRoom = $0 { return true }; return false } }
        transport.receive(.message(.joined(room: "482731", sessionID: session, state: initial)))
        try await waitUntil { coordinator.sessionID == self.session }
        await drain()
    }

    func testHostPublishesImmediateControlsAndTwoSecondHeartbeatsOnly() async throws {
        let probe = SyncPlaybackProbe()
        let (host, wire) = make(probe)
        try host.createRoom(); wire.receive(.opened)
        try await waitUntil { wire.sent.contains { if case .createRoom = $0 { return true }; return false } }
        wire.receive(.message(.roomCreated(room: "482731", sessionID: session)))
        try await waitUntil { host.latestState != nil }
        probe.position = 55; probe.playing = false
        host.publishLocalChange(.pause)
        try await waitUntil { wire.sent.filter { if case .hostState = $0 { return true }; return false }.count == 2 }
        XCTAssertEqual(host.latestState?.position, 55)
        XCTAssertEqual(host.latestState?.playing, false)
        XCTAssertEqual(host.latestState?.reason, .pause)
        let revision = host.latestState!.sequence
        time += 1.9; host.tick(); await drain()
        XCTAssertEqual(host.latestState?.sequence, revision)
        time += 0.1; host.tick()
        try await waitUntil { host.latestState?.sequence == revision + 1 }
        await host.leave()
    }

    func testStaleDuplicateAndOutOfOrderStatesCannotUndoNewerPause() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        transport.receive(.message(.state(state(sequence: 3, position: 120, playing: false))))
        try await waitUntil { coordinator.latestState?.sequence == 3 }
        let count = probe.commands.count
        transport.receive(.message(.state(state(sequence: 2, position: 500))))
        transport.receive(.message(.state(state(sequence: 3, position: 600))))
        await drain()
        XCTAssertEqual(probe.commands.count, count)
        XCTAssertEqual(probe.position, 120); XCTAssertFalse(probe.playing)
        await coordinator.leave()
    }

    func testSynchronousAndDelayedRemoteEchoNeverPublishes() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        probe.onApply = { command in
            XCTAssertTrue(coordinator.isApplyingRemoteState)
            coordinator.publishLocalChange(.pause)
            coordinator.publishLocalChange(.pause, origin: command.origin)
        }
        try await join(coordinator, transport, initial: state(playing: false))
        let origin = try XCTUnwrap(probe.commands.last?.origin)
        coordinator.publishLocalChange(.pause, origin: origin)
        await drain()
        XCTAssertFalse(transport.sent.contains { if case .hostState = $0 { return true }; return false })
        await coordinator.leave()
    }

    func testClientLocalSeekRevertsWithoutTakingAuthority() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        probe.position = 800
        coordinator.publishLocalChange(.seek)
        XCTAssertEqual(probe.position, 100)
        XCTAssertEqual(coordinator.role, .client)
        XCTAssertFalse(transport.sent.contains { if case .hostState = $0 { return true }; return false })
        await coordinator.leave()
    }

    func testBufferingKeepsNewestPauseThenCatchesUpOnce() async throws {
        let probe = SyncPlaybackProbe(); probe.buffering = true
        let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        transport.receive(.message(.state(state(sequence: 2, position: 130, playing: false))))
        try await waitUntil { coordinator.latestState?.sequence == 2 }
        XCTAssertTrue(probe.commands.isEmpty)
        time += 4; probe.buffering = false; coordinator.playbackReadinessChanged()
        XCTAssertEqual(probe.commands.count, 1)
        XCTAssertEqual(probe.position, 130); XCTAssertFalse(probe.playing)
        XCTAssertTrue(probe.commands[0].shouldSeek)
        await coordinator.leave()
    }

    func testBufferedPlayingHeartbeatIsProjectedAgainWhenReady() async throws {
        let probe = SyncPlaybackProbe(); probe.ready = false
        let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        time += 0.8; probe.ready = true; coordinator.playbackReadinessChanged()
        XCTAssertEqual(probe.position, 100.8, accuracy: 0.001)
        await coordinator.leave()
    }

    func testReconnectRequestsSnapshotAndAcceptsEqualSequenceOnce() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state(sequence: 7))
        transport.receive(.closed(.connection))
        try await waitUntil { coordinator.connectionState == .reconnecting(attempt: 1) }
        probe.position = 600
        coordinator.reconnectNow(); transport.receive(.opened)
        try await waitUntil { transport.sent.filter { if case .joinRoom = $0 { return true }; return false }.count == 2 }
        transport.receive(.message(.joined(room: "482731", sessionID: session, state: state(sequence: 7))))
        try await waitUntil { probe.position == 100 }
        let count = probe.commands.count
        transport.receive(.message(.state(state(sequence: 7, position: 700))))
        await drain(); XCTAssertEqual(probe.commands.count, count)
        XCTAssertTrue(probe.commands.last!.shouldSeek)
        await coordinator.leave()
    }

    func testDifferentRoomIncarnationCannotBeJoinedOnReconnect() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        transport.receive(.closed(.connection)); await drain()
        coordinator.reconnectNow(); transport.receive(.opened); await drain()
        transport.receive(.message(.joined(room: "482731", sessionID: UUID(), state: nil)))
        try await waitUntil { coordinator.connectionState == .closed(.hostDisconnected) }
        XCTAssertFalse(transport.isConnected)
    }

    func testMismatchStopsInsteadOfApplyingOrChangingMedia() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport)
        let other = WatchTogetherMediaDescriptor(tmdbID: 604, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
        transport.receive(.message(.state(state(media: other))))
        try await waitUntil { coordinator.connectionState == .mismatch }
        XCTAssertTrue(probe.commands.isEmpty); XCTAssertEqual(probe.media.tmdbID, 603)
    }

    func testExpiredStateRequestsSnapshotAndDoesNotSeek() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        let count = probe.commands.count
        transport.receive(.message(.state(state(sequence: 2, position: 700, sentAt: 900))))
        try await waitUntil { transport.sent.filter { if case .joinRoom = $0 { return true }; return false }.count == 2 }
        XCTAssertEqual(probe.commands.count, count)
        XCTAssertEqual(coordinator.latestState?.sequence, 1)
        await coordinator.leave()
    }

    func testSmallExplicitHostSeekStillAppliesWhileHeartbeatDoesNotSeek() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        transport.receive(.message(.state(state(sequence: 2, position: 101))))
        try await waitUntil { probe.commands.count == 2 }
        XCTAssertFalse(probe.commands.last!.shouldSeek)
        transport.receive(.message(.state(state(sequence: 3, position: 101, reason: .seek))))
        try await waitUntil { probe.commands.count == 3 }
        XCTAssertTrue(probe.commands.last!.shouldSeek); XCTAssertEqual(probe.position, 101)
        await coordinator.leave()
    }

    func testExpiredSnapshotReplyReconnectsInsteadOfApplyingStalePlayback() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport, initial: state())
        let count = probe.commands.count
        transport.receive(.message(.state(state(sequence: 2, sentAt: 900))))
        try await waitUntil { transport.sent.filter { if case .joinRoom = $0 { return true }; return false }.count == 2 }
        transport.receive(.message(.joined(room: "482731", sessionID: session, state: state(sentAt: 900))))
        try await waitUntil { coordinator.connectionState == .reconnecting(attempt: 1) }
        XCTAssertEqual(probe.commands.count, count)
        XCTAssertFalse(transport.isConnected)
        await coordinator.leave()
    }

    func testHostDisconnectClosesWithoutHostElectionAndLeaveCancelsTimers() async throws {
        let probe = SyncPlaybackProbe(); let (host, transport) = make(probe)
        try host.createRoom(); transport.receive(.opened); await drain()
        transport.receive(.message(.roomCreated(room: "482731", sessionID: session))); await drain()
        transport.receive(.closed(.connection))
        try await waitUntil { host.connectionState == .closed(.hostDisconnected) }
        XCTAssertNil(host.role); XCTAssertEqual(transport.connectionCount, 1)
        time += 30; host.tick(); await drain()
        XCTAssertEqual(transport.connectionCount, 1)
    }

    func testProtocolFailureDoesNotReconnectAndRoomExpirationStopsSync() async throws {
        let probe = SyncPlaybackProbe(); let (coordinator, transport) = make(probe)
        try await join(coordinator, transport)
        transport.receive(.message(.roomClosed(room: "482731", sessionID: session, reason: .expired)))
        try await waitUntil { coordinator.connectionState == .closed(.expired) }
        XCTAssertFalse(transport.isConnected)
        let (second, wire) = make(probe)
        try await join(second, wire)
        wire.receive(.closed(.protocolViolation))
        try await waitUntil { second.connectionState == .failed }
        XCTAssertEqual(wire.connectionCount, 1)
    }
}
