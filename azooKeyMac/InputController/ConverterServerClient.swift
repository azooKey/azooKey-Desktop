import Core
import Foundation

private enum ConverterServerXPC {
    static let machServiceName = "dev.ensan.inputmethod.azooKeyMac.ConverterServer"
}

@objc private protocol ConverterServerXPCProtocol {
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

@MainActor
final class ConverterServerClient {
    private static let commandTimeout: TimeInterval = 1

    private var connection: NSXPCConnection?
    private var sessionID: String?
    private var hasOpenedSession = false
    private var shouldAttemptReconnect = false
    private var nextReconnectAttemptDate = Date.distantPast
    private let commandQueue = OrderedAsyncCommandQueue<ConverterServerResponse?>()

    nonisolated init() {}

    var onLog: ((String) -> Void)?
    var hasOpenSession: Bool {
        sessionID != nil
    }
    var canSendOrReconnect: Bool {
        sessionID != nil || !hasOpenedSession || (shouldAttemptReconnect && Date() >= nextReconnectAttemptDate)
    }
    var pendingCommandCount: Int {
        commandQueue.count
    }

    func closeSession() {
        guard let sessionID else {
            invalidateConnection()
            return
        }
        remoteObjectProxy { [weak self] proxy in
            proxy?.closeSession(sessionID) { _ in
                Task { @MainActor in
                    self?.invalidateConnection()
                }
            }
        }
    }

    func ping(_ message: String, completion: @escaping (String?) -> Void) {
        remoteObjectProxy { proxy in
            proxy?.ping(message) { response in
                completion(response)
            }
            if proxy == nil {
                completion(nil)
            }
        }
    }

    func listSettings(
        capabilities: ConverterSettingClientCapabilities,
        completion: @escaping ([ConverterSettingDescriptor]?) -> Void
    ) {
        send(
            { _ in
                .settings(.list(capabilities: capabilities))
            },
            completion: { response in
                completion(response?.settings)
            }
        )
    }

    func updateSetting(
        key: String,
        value: ConverterSettingValue,
        completion: @escaping (Bool) -> Void
    ) {
        send(
            { _ in
                .settings(.update(key: key, value: value))
            },
            completion: { response in
                completion(response != nil)
            }
        )
    }

    func restartServer(completion: @escaping (Bool) -> Void) {
        enqueueGlobal(.shutdown) { [weak self] response in
            self?.invalidateConnection()
            completion(response != nil)
        }
    }

    func synchronizeUserDictionary(
        forceExport: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        enqueueGlobal(.maintenance(.synchronizeUserDictionary(forceExport: forceExport))) { response in
            completion(response != nil)
        }
    }

    func resetLearningData(completion: @escaping (Bool) -> Void) {
        enqueueGlobal(.maintenance(.resetLearningData)) { response in
            completion(response != nil)
        }
    }

    func send(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        enqueue(commandBuilder, retriesOnFailure: false, completion: completion)
    }

    /// キーイベントはタイムアウトで捨てず、1件ずつ順番に Server へ送る。
    /// XPC が一時的に切断した場合も先頭イベントを保持して再接続後に再送する。
    func sendKeyEvent(
        _ request: ConverterKeyEventRequest,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        enqueue({ _ in .handleKeyEvent(request) }, retriesOnFailure: true, completion: completion)
    }

    func sendIfSessionOpen(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        guard sessionID != nil else {
            completion(nil)
            return
        }
        enqueue(commandBuilder, retriesOnFailure: false, completion: completion)
    }

    private func enqueue(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        retriesOnFailure: Bool,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        var proposedSessionID: String?
        commandQueue.enqueue(
            timeout: Self.commandTimeout,
            timeoutOutcome: retriesOnFailure ? .retry : .finish(nil),
            onTimeout: { [weak self] in
                self?.handleCommandTimeout()
            },
            operation: { [weak self] finish in
                guard let self else {
                    finish(.finish(nil))
                    return
                }
                let reconnectDelay = self.nextReconnectAttemptDate.timeIntervalSinceNow
                if self.shouldAttemptReconnect, reconnectDelay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) {
                        finish(.retry)
                    }
                    return
                }
                let sessionID = self.sessionID ?? proposedSessionID ?? UUID().uuidString
                proposedSessionID = sessionID
                let sessionCommand = commandBuilder(sessionID)
                let command: ConverterServerCommand = if self.sessionID == nil {
                    .openSession(sessionID: sessionID, command: sessionCommand)
                } else {
                    .session(sessionID: sessionID, command: sessionCommand)
                }
                self.sendResolved(command) { [weak self] response in
                    guard let self else {
                        finish(.finish(nil))
                        return
                    }
                    if response != nil, self.sessionID == nil {
                        self.acceptOpenedSession(sessionID)
                    }
                    if response == nil, retriesOnFailure {
                        self.recordReconnectFailure()
                        finish(.retry)
                    } else {
                        finish(.finish(response))
                    }
                }
            },
            completion: { response in
                completion(response)
            }
        )
    }

    private func enqueueGlobal(
        _ command: ConverterServerCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        commandQueue.enqueue(
            timeout: Self.commandTimeout,
            timeoutOutcome: .finish(nil),
            onTimeout: { [weak self] in
                self?.handleCommandTimeout()
            },
            operation: { [weak self] finish in
                guard let self else {
                    finish(.finish(nil))
                    return
                }
                self.sendResolved(command) { response in
                    finish(.finish(response))
                }
            },
            completion: { response in
                completion(response)
            }
        )
    }

    private func remoteObjectProxy(completion: @escaping (ConverterServerXPCProtocol?) -> Void) {
        let connection = ensureConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            DispatchQueue.main.async {
                self?.onLog?("ConverterServer XPC error: \(error.localizedDescription)")
                self?.resetConnection(preservingSession: true)
                completion(nil)
            }
        }) as? ConverterServerXPCProtocol else {
            completion(nil)
            return
        }
        completion(proxy)
    }

    private func sendResolved(
        _ command: ConverterServerCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        do {
            let data = try ConverterServerCodec.encode(command)
            self.remoteObjectProxy { proxy in
                guard let proxy else {
                    completion(nil)
                    return
                }
                proxy.handleCommand(data) { [weak self] responseData, errorMessage in
                    let errorDescription = errorMessage.map(String.init)
                    DispatchQueue.main.async {
                        if let errorDescription {
                            self?.onLog?("ConverterServer command failed: \(errorDescription)")
                            if errorDescription.hasPrefix("Unknown converter session:") {
                                self?.resetConnection(preservingSession: false)
                            }
                            completion(nil)
                            return
                        }
                        guard let responseData else {
                            completion(nil)
                            return
                        }
                        completion(try? ConverterServerCodec.decodeResponse(from: responseData))
                    }
                }
            }
        } catch {
            self.onLog?("ConverterServer encode failed: \(error.localizedDescription)")
            completion(nil)
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = NSXPCConnection(machServiceName: ConverterServerXPC.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.onLog?("ConverterServer connection interrupted")
                self?.resetConnection(preservingSession: true)
            }
        }
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.onLog?("ConverterServer connection invalidated")
                self?.resetConnection(preservingSession: true)
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func resetConnection(preservingSession: Bool) {
        let connection = self.connection
        self.connection = nil
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        if sessionID != nil || hasOpenedSession {
            shouldAttemptReconnect = true
        }
        if !preservingSession {
            self.sessionID = nil
        }
    }

    private func invalidateConnection() {
        resetConnection(preservingSession: false)
    }

    private func recordReconnectFailure() {
        shouldAttemptReconnect = true
        nextReconnectAttemptDate = Date().addingTimeInterval(0.2)
    }

    private func acceptOpenedSession(_ sessionID: String) {
        self.sessionID = sessionID
        hasOpenedSession = true
        shouldAttemptReconnect = false
        nextReconnectAttemptDate = .distantPast
        onLog?("ConverterServer session opened: \(sessionID)")
    }

    private func handleCommandTimeout() {
        onLog?("ConverterServer command timed out")
        recordReconnectFailure()
        resetConnection(preservingSession: true)
    }
}
