import Foundation

enum EclipseSyncConfiguration {
    static func serverURL(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let value = environment["ECLIPSE_SYNC_SERVER_URL"]
            ?? bundle.object(forInfoDictionaryKey: "ECLIPSE_SYNC_SERVER_URL") as? String ?? ""
        return try validatedURL(value)
    }

    static func validatedURL(_ value: String, allowsLoopback: Bool = false) throws -> URL {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else { throw EclipseSyncProtocolError.invalidEndpoint }
        var permitsLoopback = allowsLoopback
#if DEBUG
        permitsLoopback = true
#endif
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard components.scheme?.lowercased() == "wss"
                || (permitsLoopback && loopback && components.scheme?.lowercased() == "ws") else {
            throw EclipseSyncProtocolError.invalidEndpoint
        }
        return url
    }
}

enum EclipseSyncTransportFailure: Equatable { case disconnected, connection, protocolViolation }
enum EclipseSyncTransportEvent: Equatable {
    case opened
    case message(EclipseSyncMessage)
    case closed(EclipseSyncTransportFailure)
}

@MainActor
protocol EclipseSyncTransport: AnyObject {
    var events: AsyncStream<EclipseSyncTransportEvent> { get }
    func connect() throws
    func send(_ message: EclipseSyncMessage) async throws
    func disconnect()
}

/// Networking stays outside the player. A new task/session invalidates callbacks from older sockets.
@MainActor
final class EclipseSyncWebSocketTransport: NSObject, EclipseSyncTransport, URLSessionWebSocketDelegate {
    let events: AsyncStream<EclipseSyncTransportEvent>
    private let continuation: AsyncStream<EclipseSyncTransportEvent>.Continuation
    private let endpoint: URL
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(endpoint: URL) throws {
        self.endpoint = try EclipseSyncConfiguration.validatedURL(endpoint.absoluteString)
        let pair = AsyncStream<EclipseSyncTransportEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        events = pair.stream
        continuation = pair.continuation
        super.init()
    }

    func connect() throws {
        disconnect()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let socket = session.webSocketTask(with: endpoint)
        socket.maximumMessageSize = EclipseSyncMessage.maximumBytes
        self.session = session
        self.socket = socket
        socket.resume()
    }

    func send(_ message: EclipseSyncMessage) async throws {
        guard let socket, socket.state == .running else { throw EclipseSyncTransportError.notConnected }
        let data = try message.encoded()
        guard let json = String(data: data, encoding: .utf8) else { throw EclipseSyncProtocolError.invalidMessage }
        try await socket.send(.string(json))
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        let oldSocket = socket
        socket = nil
        oldSocket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        session = nil
    }

    private func closed(_ task: URLSessionWebSocketTask, reason: EclipseSyncTransportFailure) {
        guard socket === task else { return }
        disconnect()
        continuation.yield(.closed(reason))
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor [weak self] in
            guard let self, self.socket === webSocketTask else { return }
            self.continuation.yield(.opened)
            self.receiveTask = Task { @MainActor [weak self, weak webSocketTask] in
                guard let webSocketTask else { return }
                while !Task.isCancelled {
                    do {
                        let frame = try await webSocketTask.receive()
                        guard let self, self.socket === webSocketTask else { return }
                        let data: Data
                        switch frame {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let binary): data = binary
                        @unknown default: throw EclipseSyncProtocolError.invalidMessage
                        }
                        let message = try EclipseSyncMessage.decode(data)
                        if case .dropped = self.continuation.yield(.message(message)) {
                            self.closed(webSocketTask, reason: .protocolViolation)
                            return
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.closed(webSocketTask, reason: error is EclipseSyncProtocolError || error is DecodingError
                            ? .protocolViolation : .connection)
                        return
                    }
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                               didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor [weak self] in self?.closed(webSocketTask, reason: .disconnected) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let socket = task as? URLSessionWebSocketTask else { return }
        Task { @MainActor [weak self] in self?.closed(socket, reason: .connection) }
    }

    deinit {
        receiveTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        continuation.finish()
    }
}

enum EclipseSyncTransportError: Error { case notConnected, simulatedFailure }

/// Deterministic in-memory peer used by tests; it never creates a socket or touches credentials.
@MainActor
final class EclipseSyncMockTransport: EclipseSyncTransport {
    let events: AsyncStream<EclipseSyncTransportEvent>
    private let continuation: AsyncStream<EclipseSyncTransportEvent>.Continuation
    private(set) var sent: [EclipseSyncMessage] = []
    private(set) var connectionCount = 0
    private(set) var isConnected = false
    var failNextSend = false
    var onSend: ((EclipseSyncMessage) -> Void)?

    init() {
        let pair = AsyncStream<EclipseSyncTransportEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        events = pair.stream
        continuation = pair.continuation
    }

    func connect() throws { connectionCount += 1; isConnected = true }
    func disconnect() { isConnected = false }
    func send(_ message: EclipseSyncMessage) async throws {
        guard isConnected else { throw EclipseSyncTransportError.notConnected }
        if failNextSend { failNextSend = false; throw EclipseSyncTransportError.simulatedFailure }
        _ = try message.encoded()
        sent.append(message)
        onSend?(message)
    }
    func receive(_ event: EclipseSyncTransportEvent) {
        if case .closed = event { isConnected = false }
        continuation.yield(event)
    }
}
