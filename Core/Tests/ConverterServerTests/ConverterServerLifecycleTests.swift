@testable import ConverterServer
import Core
import Foundation
import Testing

@MainActor
private func makeServer() -> ConverterServer {
    ConverterServer(makeManager: {
        SegmentsManager(
            kanaKanjiConverter: $0,
            applicationDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
    }, applyRequestSettings: { _ in })
}

private let config = ConverterSessionConfig(
    aiBackendPreference: .off,
    openAIModelName: "test",
    openAIEndpoint: "https://example.com",
    openAIAPIKey: .init(""),
    includeContextInAITransform: false
)

private func key(_ activation: ConverterSessionActivation?, id: UInt64 = 1) -> ConverterSessionCommand {
    .handleKeyEvent(.init(
        eventID: id,
        event: .init(modifierFlags: [], characters: "b", charactersIgnoringModifiers: "b", keyCode: 11),
        inputStyle: .defaultRomanToKana,
        liveConversionEnabled: false,
        enableDebugWindow: false,
        enableSuggestion: false,
        activation: activation
    ))
}

@MainActor
@Test func firstJapaneseKeyAfterActivationInEnglishIsNotInsertedAsRomanText() async throws {
    let server = makeServer()
    let owner = UUID()
    var state = ConverterClientSessionState()
    state.inputLanguage = .english
    state.activate()
    state.inputLanguage = .japanese // setValue が activate より後に来る順序
    _ = try await server.execute(.openSession(sessionID: "session", command: .lifecycle(.synchronizeInputLanguage(.japanese))), owner: owner)
    let response = try await server.execute(
        .session(sessionID: "session", command: key(state.takeActivation(config: config))), owner: owner
    )
    #expect(response.inputLanguage == .japanese)
    #expect(response.inputState == .composing)
    #expect(response.handled)
    #expect(!response.snapshot.isEmpty)
    #expect(!response.effects.contains(.insertText("b")))
    server.removeSessions(ownedBy: owner)
}

@MainActor
@Test func oldCapturedActivationReproducesRomanInputBug() async throws {
    let server = makeServer()
    let owner = UUID()
    let stale = ConverterSessionActivation(config: config, inputLanguage: .english)
    _ = try await server.execute(.openSession(sessionID: "session", command: .lifecycle(.synchronizeInputLanguage(.japanese))), owner: owner)
    let response = try await server.execute(.session(sessionID: "session", command: key(stale)), owner: owner)
    #expect(response.inputLanguage == .english)
    #expect(response.effects.contains(.insertText("b")))
    server.removeSessions(ownedBy: owner)
}

@MainActor
@Test func disconnectedOwnersAreCollectedWithoutDeletingReconnectedSession() async throws {
    let server = makeServer()
    let oldOwner = UUID()
    let newOwner = UUID()
    _ = try await server.execute(.openSession(sessionID: "abandoned", command: .composition(.snapshot)), owner: oldOwner)
    _ = try await server.execute(.openSession(sessionID: "resumed", command: .composition(.snapshot)), owner: oldOwner)
    _ = try await server.execute(.session(sessionID: "resumed", command: .composition(.snapshot)), owner: newOwner)
    server.removeSessions(ownedBy: oldOwner)
    #expect(throws: (any Error).self) { try server.getSession("abandoned") }
    #expect(throws: Never.self) { try server.getSession("resumed") }
    server.removeSessions(ownedBy: newOwner)
    #expect(throws: (any Error).self) { try server.getSession("resumed") }
}

@MainActor
@Test func deactivationClearsCompositionBeforeNextActivation() async throws {
    let server = makeServer()
    let owner = UUID()
    let activation = ConverterSessionActivation(config: config, inputLanguage: .japanese)
    _ = try await server.execute(.openSession(sessionID: "session", command: key(activation)), owner: owner)
    _ = try await server.execute(.session(sessionID: "session", command: .lifecycle(.deactivate)), owner: owner)
    let response = try await server.execute(.session(sessionID: "session", command: key(activation, id: 2)), owner: owner)
    #expect(response.snapshot.convertTarget == "b", "前回の b が復活して bb にならない")
    server.removeSessions(ownedBy: owner)
}

private final class TestListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let server: ConverterServer
    let listener = NSXPCListener.anonymous()

    init(server: ConverterServer) {
        self.server = server
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let handler = ConverterServerConnection(server: server, cleanupDelay: 0)
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = handler
        connection.invalidationHandler = { handler.invalidate() }
        connection.resume()
        return true
    }
}

@MainActor
@Test func actualXPCDisconnectCollectsServerSession() async throws {
    let server = makeServer()
    let service = TestListener(server: server)
    defer { service.listener.invalidate() }
    let connection = NSXPCConnection(listenerEndpoint: service.listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
    connection.resume()
    defer { connection.invalidate() }
    let data = try ConverterServerCodec.encode(ConverterServerCommand.openSession(
        sessionID: "xpc-session", command: .composition(.snapshot)
    ))
    let result: Data = try await withCheckedThrowingContinuation { continuation in
        let proxy = connection.remoteObjectProxyWithErrorHandler { continuation.resume(throwing: $0) }
        guard let proxy = proxy as? ConverterServerXPCProtocol else {
            continuation.resume(throwing: NSError(domain: "Invalid proxy", code: 1))
            return
        }
        proxy.handleCommand(data) { response, error in
            if let response {
                continuation.resume(returning: response)
            } else {
                continuation.resume(throwing: NSError(domain: error.map(String.init) ?? "Missing response", code: 1))
            }
        }
    }
    #expect(try ConverterServerCodec.decodeResponse(from: result).snapshot.isEmpty)
    #expect(throws: Never.self) { try server.getSession("xpc-session") }
    connection.invalidate()
    let deadline = Date().addingTimeInterval(2)
    while (try? server.getSession("xpc-session")) != nil, Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(throws: (any Error).self) { try server.getSession("xpc-session") }
}

@MainActor
@Test func invalidatedConnectionCannotCreateAnotherSession() async throws {
    let server = makeServer()
    let handler = ConverterServerConnection(server: server, cleanupDelay: 0)
    handler.invalidate()
    let data = try ConverterServerCodec.encode(ConverterServerCommand.openSession(
        sessionID: "late", command: .composition(.snapshot)
    ))
    let result: (Data?, String?) = await withCheckedContinuation { continuation in
        handler.handleCommand(data) { response, error in
            continuation.resume(returning: (response, error.map(String.init)))
        }
    }
    #expect(result.0 == nil)
    #expect(result.1 != nil)
    #expect(throws: (any Error).self) { try server.getSession("late") }
}
