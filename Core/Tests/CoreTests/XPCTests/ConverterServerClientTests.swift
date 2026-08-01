#if os(macOS)

@testable import Core
import Foundation
import Testing

@Test func converterServerClientReusesSessionForSettingsRequests() async {
    let fixture = ConverterServerClientFixture()

    let firstSettings = await listSettings(client: fixture.client)
    let secondSettings = await listSettings(client: fixture.client)

    #expect(firstSettings?.map(\.key) == [Config.TypeBackSlash.key])
    #expect(secondSettings?.map(\.key) == [Config.TypeBackSlash.key])
    #expect(fixture.server.sessionOpenCount == 1)
    #expect(fixture.server.sessionIDs == ["session-1", "session-1"])
}

@Test func converterServerClientReportsSettingUpdateResult() async {
    let fixture = ConverterServerClientFixture()

    let updated = await withCheckedContinuation { continuation in
        fixture.client.updateSetting(
            key: Config.TypeBackSlash.key,
            value: .bool(true)
        ) { success in
            continuation.resume(returning: success)
        }
    }

    #expect(updated)
    #expect(fixture.server.receivedSettingUpdate == .bool(true))
}

@Test func converterServerClientInvalidatesSessionAfterRestart() async {
    let fixture = ConverterServerClientFixture()
    _ = await listSettings(client: fixture.client)
    #expect(fixture.client.hasOpenSession)

    let restarted = await withCheckedContinuation { continuation in
        fixture.client.restartServer { success in
            continuation.resume(returning: success)
        }
    }

    #expect(restarted)
    #expect(fixture.server.receivedShutdown)
    #expect(!fixture.client.hasOpenSession)
}

private func listSettings(client: ConverterServerClient) async -> [ConverterSettingDescriptor]? {
    await withCheckedContinuation { continuation in
        client.listSettings(
            capabilities: ConverterSettingClientCapabilities(
                supportedKinds: [.toggle],
                supportedActions: [],
                supportedCustomSurfaces: []
            )
        ) { settings in
            continuation.resume(returning: settings)
        }
    }
}

private final class ConverterServerClientFixture: @unchecked Sendable {
    let client: ConverterServerClient
    let server: FakeConverterServer
    private let listener: NSXPCListener
    private let listenerDelegate: FakeConverterServerListenerDelegate

    init() {
        let server = FakeConverterServer()
        let listenerDelegate = FakeConverterServerListenerDelegate(server: server)
        let listener = NSXPCListener.anonymous()
        listener.delegate = listenerDelegate
        let endpoint = listener.endpoint
        listener.resume()

        self.server = server
        self.listenerDelegate = listenerDelegate
        self.listener = listener
        self.client = ConverterServerClient {
            NSXPCConnection(listenerEndpoint: endpoint)
        }
    }

    deinit {
        listener.invalidate()
    }
}

private final class FakeConverterServerListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let server: FakeConverterServer

    init(server: FakeConverterServer) {
        self.server = server
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = self.server
        connection.resume()
        return true
    }
}

private final class FakeConverterServer: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [ConverterServerCommand] = []
    private var openCount = 0

    var sessionOpenCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return openCount
    }

    var sessionIDs: [String] {
        commandSnapshot.compactMap { command in
            guard case .session(let sessionID, _) = command else {
                return nil
            }
            return sessionID
        }
    }

    var receivedSettingUpdate: ConverterSettingValue? {
        let updates: [ConverterSettingValue] = commandSnapshot.compactMap { command in
            guard case .session(_, .settings(.update(_, let value))) = command else {
                return nil
            }
            return value
        }
        return updates.last
    }

    var receivedShutdown: Bool {
        commandSnapshot.contains { command in
            if case .shutdown = command {
                return true
            }
            return false
        }
    }

    private var commandSnapshot: [ConverterServerCommand] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return commands
    }

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        lock.lock()
        openCount += 1
        let sessionID = "session-\(openCount)"
        lock.unlock()
        reply(sessionID)
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        reply(true)
    }

    func handleCommand(
        _ data: Data,
        with reply: @escaping @Sendable (Data?, NSString?) -> Void
    ) {
        do {
            let command = try ConverterServerCodec.decodeCommand(from: data)
            lock.lock()
            commands.append(command)
            lock.unlock()

            let settings: [ConverterSettingDescriptor]
            if case .session(_, .settings(.list)) = command {
                settings = [
                    ConverterSettingDescriptor(
                        key: Config.TypeBackSlash.key,
                        title: "Backslash",
                        section: "Test",
                        kind: .toggle,
                        value: .bool(true),
                        requiresClientUpdate: false
                    )
                ]
            } else {
                settings = []
            }
            let response = ConverterServerResponse(settings: settings, snapshot: .empty)
            reply(try ConverterServerCodec.encode(response), nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply(message)
    }
}

#endif
