import Core
import Foundation
import XCTest

@testable import azooKeyMac

/// 実際の NSXPCConnection を使い、返信が MainActor を経由せずに同期待ちを解除することを検証する。
private final class TestConverterService: NSObject, NSXPCListenerDelegate, ConverterServerXPCProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var data: Data?
        var delay: TimeInterval = 0
        var error: String?
    }

    let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []
    private var receivedCommands: [ConverterServerCommand] = []
    private var closedSessionIDs: [String] = []
    private let responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = self
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.resume()
        return true
    }

    var commands: [ConverterServerCommand] {
        lock.lock()
        defer { lock.unlock() }
        return receivedCommands
    }

    var closedSessions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return closedSessionIDs
    }

    func stop() {
        lock.lock()
        let connections = self.connections
        self.connections.removeAll()
        lock.unlock()
        connections.forEach { $0.invalidate() }
        listener.invalidate()
    }

    func openSession(with reply: @escaping @Sendable (String) -> Void) { reply(UUID().uuidString) }
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        closedSessionIDs.append(sessionID)
        lock.unlock()
        reply(true)
    }
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) { reply(message) }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        guard let command = try? ConverterServerCodec.decodeCommand(from: data) else {
            reply(nil, "invalid request")
            return
        }
        lock.lock()
        let index = receivedCommands.count
        receivedCommands.append(command)
        let response = responses.indices.contains(index) ? responses[index] : Response(error: "unexpected request")
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) {
            reply(response.data, response.error.map { $0 as NSString })
        }
    }
}

@MainActor
final class ThinClientInputPipelineTests: XCTestCase {
    private func makeClient(_ service: TestConverterService, timeout: TimeInterval = 2) -> ConverterServerClient {
        ConverterServerClient(keyEventTimeout: timeout, commandTimeout: timeout) {
            NSXPCConnection(listenerEndpoint: service.listener.endpoint)
        }
    }

    private func encodedResponse(handled: Bool = true, state: ConverterInputState = .none) throws -> Data {
        try ConverterServerCodec.encode(ConverterServerResponse(handled: handled, inputState: state, snapshot: .empty))
    }

    private func keyRequest(id: UInt64 = 1) -> ConverterKeyEventRequest {
        .init(
            eventID: id,
            event: .init(modifierFlags: [], characters: "a", charactersIgnoringModifiers: "a", keyCode: 0),
            inputStyle: .defaultRomanToKana,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false
        )
    }

    func testSynchronousCallReceivesReplyWithoutRunningMainQueue() throws {
        let service = TestConverterService(responses: [
            .init(data: try encodedResponse(state: .composing), delay: 0.02)
        ])
        defer { service.stop() }
        let client = makeClient(service)

        let response = client.sendKeyEvent(keyRequest())

        XCTAssertEqual(response?.inputState, .composing)
        XCTAssertEqual(service.commands.count, 1)
        guard case .openSession(_, .handleKeyEvent(let request)) = service.commands[0] else {
            return XCTFail("The first key must open the session atomically")
        }
        XCTAssertEqual(request.eventID, 1)
    }

    func testServerFallthroughIsReturnedSynchronously() throws {
        let service = TestConverterService(responses: [.init(data: try encodedResponse(handled: false))])
        defer { service.stop() }
        let client = makeClient(service)

        let response = client.sendKeyEvent(keyRequest())

        XCTAssertEqual(response?.handled, false)
    }

    func testEarlierAsyncCommandCompletionIsAppliedBeforeSynchronousRequest() async throws {
        let service = TestConverterService(responses: [
            .init(data: try encodedResponse(), delay: 0.02),
            .init(data: try encodedResponse(state: .composing))
        ])
        defer { service.stop() }
        let client = makeClient(service)
        var completions: [String] = []
        client.send({ .lifecycle(.synchronizeInputLanguage(.japanese)) }) { _ in
            completions.append("language")
        }

        let response = client.sendSynchronously {
            XCTAssertEqual(completions, ["language"])
            return .composition(.snapshot)
        }
        completions.append("key")

        XCTAssertEqual(response?.inputState, .composing)
        XCTAssertEqual(service.commands.count, 2)
        guard case .openSession(let firstID, _) = service.commands[0],
              case .session(let secondID, _) = service.commands[1] else {
            return XCTFail("Expected one session shared by both commands")
        }
        XCTAssertEqual(firstID, secondID)
        await Task.yield()
        XCTAssertEqual(completions, ["language", "key"], "Queued main-thread callbacks must not apply a reply twice")
    }

    func testTimeoutDropsOldReplyAndOpensFreshSession() async throws {
        let service = TestConverterService(responses: [
            .init(data: try encodedResponse(state: .composing), delay: 0.3),
            .init(data: try encodedResponse())
        ])
        defer { service.stop() }
        let client = makeClient(service, timeout: 0.1)
        var resets = 0
        client.onSessionReset = { resets += 1 }

        XCTAssertNil(client.sendSynchronously { .composition(.snapshot) })
        XCTAssertEqual(resets, 1)
        let response = client.sendSynchronously { .composition(.snapshot) }
        XCTAssertEqual(response?.inputState, ConverterInputState.none)
        XCTAssertEqual(service.commands.count, 2)
        guard case .openSession(let firstID, _) = service.commands[0],
              case .openSession(let secondID, _) = service.commands[1] else {
            return XCTFail("A timed-out session must not be reused")
        }
        XCTAssertNotEqual(firstID, secondID)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(resets, 1, "A late reply/error must not invalidate the new session")
        XCTAssertEqual(service.commands.count, 2, "A timed-out operation must not be retried")
    }

    func testFailureAbandonsQueuedCommandsInsteadOfReplayingThem() throws {
        let service = TestConverterService(responses: [.init(error: "test failure")])
        defer { service.stop() }
        let client = makeClient(service)
        var completions = 0
        client.send({ .composition(.snapshot) }) { response in
            XCTAssertNil(response)
            completions += 1
        }
        client.send({ .composition(.commit) }) { response in
            XCTAssertNil(response)
            completions += 1
        }

        client.flushPendingCommands()

        XCTAssertEqual(completions, 2)
        XCTAssertEqual(service.commands.count, 1)
    }

    func testDeactivationIsQueuedEvenWhileSessionIsOpening() throws {
        let service = TestConverterService(responses: [
            .init(data: try encodedResponse(state: .composing), delay: 0.03),
            .init(data: try encodedResponse())
        ])
        defer { service.stop() }
        let client = makeClient(service)
        client.send({ .composition(.snapshot) }, completion: { _ in })
        var deactivated = false
        client.sendIfSessionOpen({ .lifecycle(.deactivate) }, completion: { response in
            deactivated = response != nil
        })
        client.flushPendingCommands()
        XCTAssertTrue(deactivated)
        XCTAssertEqual(service.commands.count, 2)
        guard case .session(_, .lifecycle(.deactivate)) = service.commands.last else {
            return XCTFail("deactivate must not be silently discarded while opening")
        }
    }

    func testClientDestructionClosesSessionWithoutAnotherKey() async throws {
        let service = TestConverterService(responses: [.init(data: try encodedResponse())])
        defer { service.stop() }
        var client: ConverterServerClient? = makeClient(service)
        XCTAssertNotNil(client?.sendSynchronously { .composition(.snapshot) })
        guard case .openSession(let id, _) = service.commands.first else {
            return XCTFail("Expected a session")
        }
        weak var weakClient = client
        client = nil
        XCTAssertNil(weakClient)
        let deadline = Date().addingTimeInterval(2)
        while service.closedSessions.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(service.closedSessions, [id])
    }
}
