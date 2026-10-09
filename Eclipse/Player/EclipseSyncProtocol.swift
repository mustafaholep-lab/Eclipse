import CryptoKit
import Foundation

enum EclipseSyncProtocolError: Error, Equatable {
    case unsupportedVersion, invalidMessage, oversizedMessage, invalidEndpoint
}

enum EclipseSyncRole: String, Codable { case host, client }
enum EclipseSyncStateReason: String, Codable { case heartbeat, play, pause, seek, rate }
enum EclipseSyncErrorCode: String, Codable {
    case roomNotFound = "room_not_found"
    case roomFull = "room_full"
    case mediaMismatch = "media_mismatch"
    case hostOnly = "host_only"
    case invalidMessage = "invalid_message"
    case rateLimited = "rate_limited"
}
enum EclipseSyncCloseReason: String, Codable {
    case hostLeft = "host_left"
    case hostDisconnected = "host_disconnected"
    case expired
}

struct EclipseSyncState: Codable, Equatable {
    let room: String
    let sessionID: UUID
    let media: WatchTogetherMediaDescriptor
    let mediaId: String
    let playing: Bool
    let position: Double
    let rate: Double
    let sequence: UInt64
    /// Server clock seconds, calibrated by ping/pong. No stream or subtitle metadata.
    let sentAt: TimeInterval
    let stalled: Bool
    var reason: EclipseSyncStateReason = .heartbeat

    static func identifier(for media: WatchTogetherMediaDescriptor) -> String? {
        media.stableKey.map { key in
            SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    var isValid: Bool {
        EclipseSyncMessage.validRoom(room) && media.sanitizedForTransport != nil
            && mediaId == Self.identifier(for: media)
            && position.isFinite && (0...604_800).contains(position)
            && rate.isFinite && (0.25...3).contains(rate)
            && sequence > 0 && sequence <= 9_007_199_254_740_991
            && sentAt.isFinite && sentAt > 0
    }

    func projectedPosition(at serverTime: TimeInterval, duration: Double? = nil) -> Double {
        let age = max(0, min(20, serverTime - sentAt))
        let target = position + (playing && !stalled ? age * rate : 0)
        guard let duration, duration.isFinite, duration > 0 else { return target }
        return min(target, max(0, duration - 1))
    }
}

/// A closed set of messages prevents playback URLs, headers, or credentials entering the wire.
enum EclipseSyncMessage: Equatable {
    case createRoom(media: WatchTogetherMediaDescriptor)
    case joinRoom(room: String, media: WatchTogetherMediaDescriptor)
    case leaveRoom(room: String, sessionID: UUID)
    case hostState(EclipseSyncState)
    case ping(id: UUID, sentAt: TimeInterval)
    case roomCreated(room: String, sessionID: UUID)
    case joined(room: String, sessionID: UUID, state: EclipseSyncState?)
    case participantJoined(room: String, sessionID: UUID)
    case participantLeft(room: String, sessionID: UUID)
    case state(EclipseSyncState)
    case roomClosed(room: String, sessionID: UUID, reason: EclipseSyncCloseReason)
    case error(EclipseSyncErrorCode)
    case pong(id: UUID, clientSentAt: TimeInterval, serverReceivedAt: TimeInterval, serverSentAt: TimeInterval)

    static let maximumBytes = 16_384
    static func validRoom(_ room: String) -> Bool {
        room.utf8.count == 6 && room.utf8.allSatisfy { (48...57).contains($0) }
    }

    private struct Wire: Codable {
        var protocolVersion = 1
        let type: String
        var room: String?
        var sessionID: UUID?
        var media: WatchTogetherMediaDescriptor?
        var state: EclipseSyncState?
        var id: UUID?
        var sentAt: Double?
        var clientSentAt: Double?
        var serverReceivedAt: Double?
        var serverSentAt: Double?
        var reason: EclipseSyncCloseReason?
        var code: EclipseSyncErrorCode?
    }

    func encoded() throws -> Data {
        var wire: Wire
        switch self {
        case .createRoom(let media): wire = Wire(type: "create_room", media: media)
        case .joinRoom(let room, let media): wire = Wire(type: "join_room", room: room, media: media)
        case .leaveRoom(let room, let session): wire = Wire(type: "leave_room", room: room, sessionID: session)
        case .hostState(let state): wire = Wire(type: "host_state", state: state)
        case .ping(let id, let time): wire = Wire(type: "ping", id: id, sentAt: time)
        case .roomCreated(let room, let session): wire = Wire(type: "room_created", room: room, sessionID: session)
        case .joined(let room, let session, let state): wire = Wire(type: "joined", room: room, sessionID: session, state: state)
        case .participantJoined(let room, let session): wire = Wire(type: "participant_joined", room: room, sessionID: session)
        case .participantLeft(let room, let session): wire = Wire(type: "participant_left", room: room, sessionID: session)
        case .state(let state): wire = Wire(type: "state", state: state)
        case .roomClosed(let room, let session, let reason): wire = Wire(type: "room_closed", room: room, sessionID: session, reason: reason)
        case .error(let code): wire = Wire(type: "error", code: code)
        case .pong(let id, let client, let received, let sent):
            wire = Wire(type: "pong", id: id, clientSentAt: client, serverReceivedAt: received, serverSentAt: sent)
        }
        wire.protocolVersion = 1
        let data = try JSONEncoder().encode(wire)
        _ = try Self.decode(data)
        return data
    }

    static func decode(_ data: Data) throws -> EclipseSyncMessage {
        guard data.count <= maximumBytes else { throw EclipseSyncProtocolError.oversizedMessage }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["protocolVersion"] as? Int, version == 1 else {
            throw EclipseSyncProtocolError.unsupportedVersion
        }
        guard let type = object["type"] as? String else { throw EclipseSyncProtocolError.invalidMessage }
        let fields: Set<String>
        switch type {
        case "create_room": fields = ["media"]
        case "join_room": fields = ["room", "media"]
        case "leave_room", "room_created", "participant_joined", "participant_left": fields = ["room", "sessionID"]
        case "joined": fields = ["room", "sessionID", "state"]
        case "host_state", "state": fields = ["state"]
        case "ping": fields = ["id", "sentAt"]
        case "pong": fields = ["id", "clientSentAt", "serverReceivedAt", "serverSentAt"]
        case "room_closed": fields = ["room", "sessionID", "reason"]
        case "error": fields = ["code"]
        default: throw EclipseSyncProtocolError.invalidMessage
        }
        guard Set(object.keys).isSubset(of: fields.union(["protocolVersion", "type"])) else {
            throw EclipseSyncProtocolError.invalidMessage
        }
        if let media = object["media"] { try validateMediaFields(media) }
        if let state = object["state"] as? [String: Any] {
            guard Set(state.keys) == Set(["room", "sessionID", "media", "mediaId", "playing", "position", "rate", "sequence", "sentAt", "stalled", "reason"]),
                  let media = state["media"] else { throw EclipseSyncProtocolError.invalidMessage }
            try validateMediaFields(media)
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        func membership() throws -> (String, UUID) {
            guard let room = wire.room, validRoom(room), let session = wire.sessionID else { throw EclipseSyncProtocolError.invalidMessage }
            return (room, session)
        }
        switch type {
        case "create_room", "join_room":
            guard let media = wire.media, media.sanitizedForTransport != nil else { throw EclipseSyncProtocolError.invalidMessage }
            if type == "create_room" { return .createRoom(media: media) }
            guard let room = wire.room, validRoom(room) else { throw EclipseSyncProtocolError.invalidMessage }
            return .joinRoom(room: room, media: media)
        case "host_state", "state":
            guard let state = wire.state, state.isValid else { throw EclipseSyncProtocolError.invalidMessage }
            return type == "state" ? .state(state) : .hostState(state)
        case "room_created", "joined", "participant_joined", "participant_left", "leave_room", "room_closed":
            let (room, session) = try membership()
            switch type {
            case "room_created": return .roomCreated(room: room, sessionID: session)
            case "joined":
                if let state = wire.state {
                    guard state.isValid, state.room == room, state.sessionID == session else { throw EclipseSyncProtocolError.invalidMessage }
                }
                return .joined(room: room, sessionID: session, state: wire.state)
            case "participant_joined": return .participantJoined(room: room, sessionID: session)
            case "participant_left": return .participantLeft(room: room, sessionID: session)
            case "leave_room": return .leaveRoom(room: room, sessionID: session)
            default:
                guard let reason = wire.reason else { throw EclipseSyncProtocolError.invalidMessage }
                return .roomClosed(room: room, sessionID: session, reason: reason)
            }
        case "ping":
            guard let id = wire.id, let time = wire.sentAt, time.isFinite, time > 0 else { throw EclipseSyncProtocolError.invalidMessage }
            return .ping(id: id, sentAt: time)
        case "pong":
            guard let id = wire.id, let client = wire.clientSentAt, let received = wire.serverReceivedAt, let sent = wire.serverSentAt,
                  [client, received, sent].allSatisfy({ $0.isFinite && $0 > 0 }), sent >= received else { throw EclipseSyncProtocolError.invalidMessage }
            return .pong(id: id, clientSentAt: client, serverReceivedAt: received, serverSentAt: sent)
        default:
            guard let code = wire.code else { throw EclipseSyncProtocolError.invalidMessage }
            return .error(code)
        }
    }

    private static func validateMediaFields(_ value: Any) throws {
        guard let media = value as? [String: Any], Set(media.keys).isSubset(of: ["tmdbID", "mediaType", "seasonNumber", "episodeNumber", "playbackContext", "isAnime", "title"]) else {
            throw EclipseSyncProtocolError.invalidMessage
        }
        if let context = media["playbackContext"] as? [String: Any] {
            let allowed: Set<String> = ["localSeasonNumber", "localEpisodeNumber", "anilistMediaId", "canonicalAniListMediaId", "malMediaId", "kitsuMediaId", "tmdbSeasonNumber", "tmdbEpisodeNumber", "tmdbEpisodeOffset", "animeAbsoluteEpisodeNumber", "animeSeasonEpisodeCount", "isSpecial", "titleOnlySearch"]
            guard Set(context.keys).isSubset(of: allowed) else { throw EclipseSyncProtocolError.invalidMessage }
        }
    }
}

struct EclipseSyncClock {
    private(set) var offset: TimeInterval?
    private var bestRoundTrip = Double.infinity

    mutating func record(clientSent: Double, serverReceived: Double, serverSent: Double, clientReceived: Double) -> Bool {
        let roundTrip = (clientReceived - clientSent) - (serverSent - serverReceived)
        guard [clientSent, serverReceived, serverSent, clientReceived].allSatisfy(\.isFinite),
              serverSent >= serverReceived, clientReceived >= clientSent, (0...5).contains(roundTrip) else { return false }
        if roundTrip <= bestRoundTrip {
            bestRoundTrip = roundTrip
            offset = ((serverReceived - clientSent) + (serverSent - clientReceived)) / 2
        }
        return true
    }
}

enum EclipseSyncDriftPolicy {
    static let ignoreThreshold = 0.5
    static let hardSeekThreshold = 1.5

    static func shouldSeek(local: Double, target: Double, force: Bool) -> Bool {
        local.isFinite && target.isFinite && (force || abs(local - target) > hardSeekThreshold)
    }
}
