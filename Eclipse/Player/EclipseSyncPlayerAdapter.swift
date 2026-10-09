import Foundation

/// Renderer access contains only canonical identity and playback state/control.
@MainActor
protocol EclipseSyncPlayer: AnyObject {
    var eclipseSyncPlayerSnapshot: EclipseSyncPlaybackSnapshot? { get }
    func eclipseSyncSeek(to position: Double, origin: EclipseSyncCommandOrigin)
    func eclipseSyncSetRate(_ rate: Double, origin: EclipseSyncCommandOrigin)
    func eclipseSyncSetPlaying(_ playing: Bool, origin: EclipseSyncCommandOrigin)
    func eclipseSyncUpdateStatus(_ state: EclipseSyncConnectionState)
}

@MainActor
final class EclipseSyncPlayerAdapter: EclipseSyncPlaybackDelegate {
    private(set) static weak var active: EclipseSyncPlayerAdapter?
    private weak var player: (any EclipseSyncPlayer)?
    private let transport: any EclipseSyncTransport
    private let automaticTimers: Bool
    private let now: () -> TimeInterval
    private(set) var coordinator: EclipseSyncCoordinator?
    private var applyingOrigin: EclipseSyncCommandOrigin?
    private var leaving = false
    private struct PendingSeek {
        var position: Double
        var sampledAt: Double
        var playing: Bool
        var rate: Double
        var stalled: Bool
        let expiresAt: Double
    }
    private var pendingSeek: PendingSeek?
    var onAcquirePlayback: (() -> Void)?

    init(player: any EclipseSyncPlayer, transport: any EclipseSyncTransport,
         automaticTimers: Bool = true, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.player = player; self.transport = transport
        self.automaticTimers = automaticTimers; self.now = now
    }

    var isActive: Bool { coordinator?.role != nil || leaving }
    var isClient: Bool { coordinator?.role == .client }
    var state: EclipseSyncConnectionState { coordinator?.connectionState ?? .idle }
    var room: String? { coordinator?.room }
    var role: EclipseSyncRole? { coordinator?.role }
    var statusText: String {
        switch state {
        case .idle: return "Not active"
        case .connecting: return role == .host ? "Creating room..." : "Joining room..."
        case .waitingForState: return "Client · Room \(room ?? "") · Waiting for host"
        case .active(let role, let room): return "\(role == .host ? "Host" : "Client") · Room \(room)"
        case .reconnecting(let attempt): return "Client · Room \(room ?? "") · Reconnecting (\(attempt)/5)"
        case .mismatch: return "Different movie or episode. Open the host's title before joining."
        case .closed(let reason):
            switch reason {
            case .hostLeft: return "The host left the room."
            case .hostDisconnected: return "The host disconnected. The room is closed."
            case .expired: return "The room expired. Create or join a new room."
            }
        case .rejected(let code):
            switch code {
            case .roomNotFound: return "Room not found. Check the code or ask the host for a new room."
            case .roomFull: return "The room already has a client."
            case .mediaMismatch: return "Different movie or episode."
            case .hostOnly: return "Only the host can control playback."
            case .invalidMessage: return "The server rejected the room request."
            case .rateLimited: return "Too many requests. Try again later."
            }
        case .failed: return "Eclipse Sync disconnected or could not connect. Try joining again."
        }
    }
    var controlPosition: Double? { eclipseSyncSnapshot?.position }
    var eclipseSyncSnapshot: EclipseSyncPlaybackSnapshot? {
        guard let live = player?.eclipseSyncPlayerSnapshot else { return nil }
        guard role == .host, let pending = pendingSeek else { return live }
        let elapsed = max(0, now() - pending.sampledAt)
        let position = pending.position + (pending.playing && !pending.stalled ? elapsed * pending.rate : 0)
        if now() >= pending.expiresAt || abs(live.position - position) < 0.5 {
            pendingSeek = nil
            return live
        }
        return EclipseSyncPlaybackSnapshot(media: live.media, position: position, duration: live.duration,
            playing: live.playing, rate: live.rate, ready: live.ready, buffering: live.buffering)
    }

    func start(room: String? = nil) throws {
        // A room attempt owns one stream consumer. A later attempt gets a fresh transport/adapter.
        guard coordinator == nil, !isActive, Self.active == nil || Self.active === self,
              let snapshot = eclipseSyncSnapshot, snapshot.media.sanitizedForTransport != nil,
              room.map(EclipseSyncMessage.validRoom) ?? true else { throw EclipseSyncProtocolError.invalidMessage }
        Self.active = self
        onAcquirePlayback?()
        let coordinator = EclipseSyncCoordinator(transport: transport, playback: self,
            automaticTimers: automaticTimers, now: now)
        self.coordinator = coordinator
        do {
            if let room { try coordinator.joinRoom(room) }
            else { try coordinator.createRoom() }
        } catch {
            cancel()
            throw error
        }
    }

    func leave() async {
        guard !leaving else { return }
        leaving = true
        await coordinator?.leave()
        leaving = false
        releasePlayback()
        player?.eclipseSyncUpdateStatus(.idle)
    }

    func cancel() {
        leaving = false
        pendingSeek = nil
        coordinator?.cancel()
        releasePlayback()
    }

    /// Call before explicit local controls. Clients cannot change authority, including while reconnecting.
    func permitsLocalControl(_ reason: EclipseSyncStateReason) -> Bool {
        guard isClient else { return !leaving }
        coordinator?.publishLocalChange(reason)
        return false
    }

    /// A seek/rate target must be sent immediately, before the renderer's asynchronous callback.
    func localChange(_ reason: EclipseSyncStateReason, position: Double? = nil, rate: Double? = nil,
                     origin: EclipseSyncCommandOrigin = .local) {
        guard !leaving, applyingOrigin == nil, origin == .local,
              let live = eclipseSyncSnapshot else { return }
        let snapshot = EclipseSyncPlaybackSnapshot(media: live.media, position: position ?? live.position,
            duration: live.duration, playing: live.playing, rate: rate ?? live.rate,
            ready: live.ready, buffering: live.buffering)
        if role == .host, (reason == .seek && position != nil) || pendingSeek != nil {
            let expiresAt = reason == .seek ? now() + 2 : (pendingSeek?.expiresAt ?? now() + 2)
            pendingSeek = PendingSeek(position: snapshot.position, sampledAt: now(), playing: snapshot.playing,
                rate: snapshot.rate, stalled: snapshot.buffering || !snapshot.ready,
                expiresAt: expiresAt)
        }
        coordinator?.publishLocalChange(reason, origin: origin, snapshot: snapshot)
    }

    func readinessChanged() {
        if let snapshot = eclipseSyncSnapshot, let pending = pendingSeek {
            pendingSeek = PendingSeek(position: snapshot.position, sampledAt: now(), playing: snapshot.playing,
                rate: snapshot.rate, stalled: snapshot.buffering || !snapshot.ready, expiresAt: pending.expiresAt)
        }
        coordinator?.playbackReadinessChanged()
    }

    func eclipseSyncApply(_ command: EclipseSyncPlaybackCommand) {
        guard let player, let snapshot = player.eclipseSyncPlayerSnapshot,
              snapshot.ready, !snapshot.buffering, applyingOrigin == nil else { return }
        applyingOrigin = command.origin
        defer { applyingOrigin = nil }
        if command.shouldSeek { player.eclipseSyncSeek(to: command.position, origin: command.origin) }
        if abs(snapshot.rate - command.rate) >= 0.001 {
            player.eclipseSyncSetRate(command.rate, origin: command.origin)
        }
        player.eclipseSyncSetPlaying(command.playing, origin: command.origin)
    }

    func eclipseSyncConnectionChanged(_ state: EclipseSyncConnectionState) {
        switch state {
        case .idle, .mismatch, .closed, .failed, .rejected:
            if !leaving { releasePlayback() }
        default: break
        }
        player?.eclipseSyncUpdateStatus(state)
    }

    private func releasePlayback() {
        pendingSeek = nil
        if Self.active === self { Self.active = nil }
    }
}
