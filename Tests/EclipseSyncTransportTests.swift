import Foundation
import XCTest
@testable import Eclipse

final class EclipseSyncTransportTests: XCTestCase {
    func testEndpointRequiresTLSAndCannotContainCredentialsOrQueryTokens() throws {
        XCTAssertEqual(try EclipseSyncConfiguration.validatedURL("wss://sync.example.com/ws").scheme, "wss")
        for value in ["", "https://sync.example.com", "ws://sync.example.com", "wss://user:secret@sync.example.com", "wss://sync.example.com?token=secret", "wss://sync.example.com#secret"] {
            XCTAssertThrowsError(try EclipseSyncConfiguration.validatedURL(value))
        }
        XCTAssertEqual(try EclipseSyncConfiguration.validatedURL("ws://127.0.0.1:8787", allowsLoopback: true).host, "127.0.0.1")
    }

    func testConfigurationReadsOneCentralEnvironmentKey() throws {
        XCTAssertEqual(try EclipseSyncConfiguration.serverURL(environment: ["ECLIPSE_SYNC_SERVER_URL": "wss://sync.example.com/ws"]).host, "sync.example.com")
        XCTAssertThrowsError(try EclipseSyncConfiguration.serverURL(environment: ["ECLIPSE_SYNC_SERVER_URL": "bad"]))
    }

    @MainActor
    func testMockEncodesMessagesAndDoesNotSendWhenDisconnected() async throws {
        let transport = EclipseSyncMockTransport()
        let ping = EclipseSyncMessage.ping(id: UUID(), sentAt: 1_000)
        do { try await transport.send(ping); XCTFail("Disconnected send succeeded") } catch {}
        try transport.connect(); try await transport.send(ping)
        XCTAssertEqual(transport.sent, [ping])
        transport.disconnect()
        do { try await transport.send(ping); XCTFail("Send after leave succeeded") } catch {}
        XCTAssertEqual(transport.sent.count, 1)
    }

    @MainActor
    func testMockExposesServerMessagesAndConnectionFailure() async throws {
        let transport = EclipseSyncMockTransport()
        try transport.connect()
        var iterator = transport.events.makeAsyncIterator()
        transport.receive(.opened)
        let opened = await iterator.next()
        XCTAssertEqual(opened, .opened)
        transport.receive(.message(.error(.roomFull)))
        let message = await iterator.next()
        XCTAssertEqual(message, .message(.error(.roomFull)))
        transport.receive(.closed(.connection))
        let closed = await iterator.next()
        XCTAssertEqual(closed, .closed(.connection))
        XCTAssertFalse(transport.isConnected)
    }
}
