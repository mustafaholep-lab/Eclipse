import Foundation

struct EclipseSyncPlaybackSnapshot {
    let media: WatchTogetherMediaDescriptor
    let position: Double
    let duration: Double?
    let playing: Bool
    let rate: Double
    let ready: Bool
    let buffering: Bool
}

enum EclipseSyncCommandOrigin: Equatable { case local, remote(UUID) }
struct EclipseSyncPlaybackCommand {
    let origin: EclipseSyncCommandOrigin
    let position: Double
    let playing: Bool
    let rate: Double
    let shouldSeek: Bool
    let sequence: UInt64
}

enum EclipseSyncConnectionState: Equatable {
    case idle, connecting, waitingForState
    case active(role: EclipseSyncRole, room: String)
    case reconnecting(attempt: Int)
    case mismatch
    case closed(EclipseSyncCloseReason)
    case failed
}

/// The future player adapter supplies only playback state/control, never a PlaybackRequest.
@MainActor
protocol EclipseSyncPlaybackDelegate: AnyObject {
    var eclipseSyncSnapshot: EclipseSyncPlaybackSnapshot { get }
    func eclipseSyncApply(_ command: EclipseSyncPlaybackCommand)
    func eclipseSyncConnectionChanged(_ state: EclipseSyncConnectionState)
}

@MainActor
final class EclipseSyncCoordinator {
    private(set) var connectionState: EclipseSyncConnectionState = .idle {
        didSet { if oldValue != connectionState { playback?.eclipseSyncConnectionChanged(connectionState) } }
    }
    private(set) var role: EclipseSyncRole?
    private(set) var room: String?
    private(set) var sessionID: UUID?
    private(set) var latestState: EclipseSyncState?
    private(set) var isApplyingRemoteState = false
    private weak var playback: (any EclipseSyncPlaybackDelegate)?
    private let transport: any EclipseSyncTransport
    private let now: () -> TimeInterval
    private let automaticTimers: Bool
    private var media: WatchTogetherMediaDescriptor?
    private var clock = EclipseSyncClock()
    private var pendingPings: [UUID: Double] = [:]
    private var sequence: UInt64 = 0
    private var lastReceivedSequence: UInt64 = 0
    private var forceCatchUp = true
    private var membershipConfirmed = false
    private var lastHeartbeatAt = -Double.infinity
    private var lastPingAt = -Double.infinity
    private var openedAt: Double?
    private var joinedAt: Double?
    private var lastFreshStateAt: Double?
    private var snapshotRequested = false
    private var reconnectAttempts = 0
    private var generation: UInt64 = 0
    private var pendingSends = 0
    private var eventTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?

    init(transport: any EclipseSyncTransport, playback: any EclipseSyncPlaybackDelegate,
         automaticTimers: Bool = true, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.transport = transport
        self.playback = playback
        self.automaticTimers = automaticTimers
        self.now = now
    }

    func createRoom() throws { try begin(role: .host, room: nil) }
    func joinRoom(_ room: String) throws {
        guard EclipseSyncMessage.validRoom(room) else { throw EclipseSyncProtocolError.invalidMessage }
        try begin(role: .client, room: room)
    }

    private func begin(role: EclipseSyncRole, room: String?) throws {
        guard self.role == nil, let snapshot = playback?.eclipseSyncSnapshot,
              snapshot.media.sanitizedForTransport != nil else { throw EclipseSyncProtocolError.invalidMessage }
        reset()
        self.role = role
        self.room = room
        media = snapshot.media
        connectionState = .connecting
        let events = transport.events
        eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
        do { try transport.connect() } catch { terminate(.failed); throw error }
        if automaticTimers {
            heartbeatTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    self?.tick()
                }
            }
        }
    }

    func leave() async {
        let membership = room.flatMap { room in sessionID.map { (room, $0) } }
        let currentGeneration = generation
        role = nil
        heartbeatTask?.cancel()
        reconnectTask?.cancel()
        sendTask?.cancel()
        if let (room, session) = membership {
            try? await transport.send(.leaveRoom(room: room, sessionID: session))
        }
        guard currentGeneration == generation else { return }
        reset()
        connectionState = .idle
    }

    /// Controls publish immediately. Remote origins also suppress delayed renderer callbacks.
    func publishLocalChange(_ reason: EclipseSyncStateReason, origin: EclipseSyncCommandOrigin = .local) {
        guard origin == .local, !isApplyingRemoteState, membershipConfirmed else { return }
        if role == .client {
            applyLatest(force: true)
            return
        }
        publishHostState(reason)
    }

    func playbackReadinessChanged() {
        guard membershipConfirmed else { return }
        if role == .client { applyLatest(force: forceCatchUp) }
        else { publishHostState(.heartbeat) }
    }

    /// Kept deterministic for tests; the production timer calls this twice a second.
    func tick() {
        guard role != nil, reconnectTask == nil else { return }
        if let openedAt, !membershipConfirmed || clock.offset == nil, now() - openedAt > 15 {
            connectionLost(.connection)
            return
        }
        if openedAt != nil, now() - lastPingAt >= 10 { ping() }
        guard membershipConfirmed else { return }
        if role == .host, now() - lastHeartbeatAt >= 2 { publishHostState(.heartbeat) }
        if role == .client, let receivedAt = lastFreshStateAt ?? joinedAt, now() - receivedAt > 10 {
            requestSnapshot()
            if now() - receivedAt > 20 { connectionLost(.connection) }
        }
    }

    private func handle(_ event: EclipseSyncTransportEvent) {
        guard role != nil else { return }
        switch event {
        case .opened:
            openedAt = now()
            clock = EclipseSyncClock()
            pendingPings.removeAll()
            ping()
            guard let media else { terminate(.failed); return }
            if role == .host { enqueue(.createRoom(media: media)) }
            else if let room { enqueue(.joinRoom(room: room, media: media)) }
            log("connected")
        case .message(let message): receive(message)
        case .closed(let failure): connectionLost(failure)
        }
    }

    private func receive(_ message: EclipseSyncMessage) {
        switch message {
        case .pong(let id, let clientSent, let received, let sent):
            guard pendingPings.removeValue(forKey: id) == clientSent,
                  clock.record(clientSent: clientSent, serverReceived: received, serverSent: sent, clientReceived: now()) else { return }
            if role == .client { applyLatest(force: forceCatchUp) }
            else if membershipConfirmed, latestState == nil { publishHostState(.heartbeat) }
        case .roomCreated(let room, let session):
            guard role == .host, !membershipConfirmed else { return }
            self.room = room; sessionID = session; membershipConfirmed = true
            connectionState = .active(role: .host, room: room)
            publishHostState(.heartbeat)
            log("room created")
        case .joined(let room, let session, let state):
            guard role == .client, self.room == room else { return }
            guard sessionID == nil || sessionID == session else { terminate(.closed(.hostDisconnected)); return }
            let resync = !membershipConfirmed
            sessionID = session; membershipConfirmed = true; joinedAt = now()
            snapshotRequested = false
            connectionState = .waitingForState
            if let state { accept(state, reconnectSnapshot: resync) }
        case .state(let state): accept(state, reconnectSnapshot: false)
        case .participantJoined(let room, let session):
            guard matches(room, session) else { return }
            log("client joined")
            if role == .host { publishHostState(.heartbeat) }
        case .participantLeft(let room, let session):
            guard matches(room, session) else { return }
            log("client left")
        case .roomClosed(let room, let session, let reason):
            guard matches(room, session) else { return }
            terminate(.closed(reason))
        case .error(let code):
            terminate(code == .mediaMismatch ? .mismatch : .failed)
        default:
            // A relay cannot send client/host commands back as authority.
            terminate(.failed)
        }
    }

    private func accept(_ state: EclipseSyncState, reconnectSnapshot: Bool) {
        guard role == .client, membershipConfirmed, matches(state.room, state.sessionID), state.isValid else { return }
        guard let local = playback?.eclipseSyncSnapshot, local.media.isSameLogicalMedia(as: state.media) else {
            terminate(.mismatch); return
        }
        guard state.sequence > lastReceivedSequence || (reconnectSnapshot && state.sequence == lastReceivedSequence) else {
            log("stale state ignored"); return
        }
        if let offset = clock.offset {
            let age = now() + offset - state.sentAt
            guard (-1...20).contains(age) else {
                if reconnectSnapshot || snapshotRequested { connectionLost(.connection) }
                else { requestSnapshot() }
                return
            }
        }
        lastReceivedSequence = state.sequence
        latestState = state
        lastFreshStateAt = now()
        snapshotRequested = false
        reconnectAttempts = 0
        forceCatchUp = forceCatchUp || reconnectSnapshot || state.reason == .seek || !local.ready || local.buffering
        applyLatest(force: forceCatchUp)
    }

    private func applyLatest(force: Bool) {
        guard role == .client, membershipConfirmed, let state = latestState,
              let offset = clock.offset, let playback else { return }
        let snapshot = playback.eclipseSyncSnapshot
        guard snapshot.media.isSameLogicalMedia(as: state.media) else { terminate(.mismatch); return }
        guard snapshot.ready, !snapshot.buffering else { forceCatchUp = true; return }
        guard (-1...20).contains(now() + offset - state.sentAt) else { requestSnapshot(); return }
        let target = state.projectedPosition(at: now() + offset, duration: snapshot.duration)
        let seek = EclipseSyncDriftPolicy.shouldSeek(local: snapshot.position, target: target, force: force)
        let command = EclipseSyncPlaybackCommand(origin: .remote(UUID()), position: target,
            playing: state.playing && !state.stalled, rate: state.rate, shouldSeek: seek, sequence: state.sequence)
        isApplyingRemoteState = true
        defer { isApplyingRemoteState = false }
        playback.eclipseSyncApply(command)
        forceCatchUp = false
        if let room { connectionState = .active(role: .client, room: room) }
        if seek { log(String(format: "drift correction %.2fs", abs(snapshot.position - target))) }
    }

    private func publishHostState(_ reason: EclipseSyncStateReason) {
        guard role == .host, membershipConfirmed, let room, let sessionID, let offset = clock.offset,
              let media, let snapshot = playback?.eclipseSyncSnapshot else { return }
        guard media.isSameLogicalMedia(as: snapshot.media) else { terminate(.mismatch); return }
        guard let identifier = EclipseSyncState.identifier(for: media), snapshot.position.isFinite,
              (0...604_800).contains(snapshot.position), snapshot.rate.isFinite, (0.25...3).contains(snapshot.rate),
              sequence < 9_007_199_254_740_991 else { terminate(.failed); return }
        sequence += 1
        let state = EclipseSyncState(room: room, sessionID: sessionID, media: media, mediaId: identifier,
            playing: snapshot.playing, position: snapshot.position, rate: snapshot.rate, sequence: sequence,
            sentAt: now() + offset, stalled: snapshot.buffering || !snapshot.ready, reason: reason)
        latestState = state
        lastHeartbeatAt = now()
        enqueue(.hostState(state))
    }

    private func ping() {
        let id = UUID(), time = now()
        if pendingPings.count >= 4 { pendingPings.removeAll() }
        pendingPings[id] = time
        lastPingAt = time
        enqueue(.ping(id: id, sentAt: time))
    }

    private func requestSnapshot() {
        guard role == .client, membershipConfirmed, !snapshotRequested, let room, let media else { return }
        snapshotRequested = true
        enqueue(.joinRoom(room: room, media: media))
    }

    private func matches(_ room: String, _ session: UUID) -> Bool { self.room == room && sessionID == session }

    private func enqueue(_ message: EclipseSyncMessage) {
        guard pendingSends < 16 else { connectionLost(.connection); return }
        pendingSends += 1
        let previous = sendTask, currentGeneration = generation, transport = transport
        sendTask = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.generation == currentGeneration, self.role != nil else { return }
            do { try await transport.send(message) }
            catch { if self.generation == currentGeneration { self.connectionLost(.connection) }; return }
            if self.generation == currentGeneration { self.pendingSends -= 1 }
        }
    }

    private func connectionLost(_ failure: EclipseSyncTransportFailure) {
        guard role != nil, reconnectTask == nil else { return }
        transport.disconnect()
        generation &+= 1
        sendTask?.cancel(); sendTask = nil; pendingSends = 0
        membershipConfirmed = false; openedAt = nil; clock = EclipseSyncClock()
        latestState = nil; lastFreshStateAt = nil; snapshotRequested = false
        forceCatchUp = true
        log("disconnected")
        if failure == .protocolViolation { terminate(.failed); return }
        guard role == .client else { terminate(.closed(.hostDisconnected)); return }
        guard reconnectAttempts < 5 else { terminate(.failed); return }
        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts)
        if automaticTimers {
            let delay = UInt64(1 << (reconnectAttempts - 1)) * 1_000_000_000
            reconnectTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self else { return }
                self.reconnectTask = nil
                self.reconnectNow()
            }
        }
    }

    /// Tests bypass elapsed backoff; production calls it only from the bounded reconnect task.
    func reconnectNow() {
        guard role == .client, !membershipConfirmed else { return }
        reconnectTask?.cancel(); reconnectTask = nil
        do { try transport.connect() } catch { connectionLost(.connection) }
    }

    private func terminate(_ state: EclipseSyncConnectionState) { reset(); connectionState = state }

    private func reset() {
        generation &+= 1
        eventTask?.cancel(); eventTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        sendTask?.cancel(); sendTask = nil
        transport.disconnect()
        role = nil; room = nil; sessionID = nil; media = nil; latestState = nil
        membershipConfirmed = false; sequence = 0; lastReceivedSequence = 0
        clock = EclipseSyncClock(); pendingPings.removeAll()
        pendingSends = 0; reconnectAttempts = 0; snapshotRequested = false
        openedAt = nil; joinedAt = nil; lastFreshStateAt = nil
        forceCatchUp = true; lastHeartbeatAt = -Double.infinity; lastPingAt = -Double.infinity
    }

    private func log(_ message: String) { Logger.shared.log("[EclipseSync] \(message)", type: "Player") }

    deinit {
        eventTask?.cancel()
        heartbeatTask?.cancel()
        reconnectTask?.cancel()
        sendTask?.cancel()
        let transport = transport
        Task { @MainActor in transport.disconnect() }
    }
}
