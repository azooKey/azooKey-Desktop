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
    private var connection: NSXPCConnection?
    private var sessionID: String?
    private var hasOpenedSession = false
    private var shouldAttemptReconnect = false
    private var nextReconnectAttemptDate = Date.distantPast
    private var isOpeningSession = false
    private var openSessionCompletions: [(String?) -> Void] = []
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

    func openSession(completion: ((String?) -> Void)? = nil) {
        if let sessionID {
            completion?(sessionID)
            return
        }
        if let completion {
            openSessionCompletions.append(completion)
        }
        guard !isOpeningSession else {
            return
        }
        isOpeningSession = true
        openSessionOnServer { [weak self] sessionID in
            guard let self else {
                return
            }
            self.isOpeningSession = false
            let completions = self.openSessionCompletions
            self.openSessionCompletions.removeAll()
            completions.forEach { $0(sessionID) }
        }
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
        guard sessionID != nil || isOpeningSession else {
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
        commandQueue.enqueue(
            operation: { [weak self] finish in
                guard let self else {
                    finish(.finish(nil))
                    return
                }
                self.openSession { [weak self] sessionID in
                    guard let self, let sessionID else {
                        finish(retriesOnFailure ? .retry : .finish(nil))
                        return
                    }
                    self.sendResolved(
                        .session(sessionID: sessionID, command: commandBuilder(sessionID))
                    ) { [weak self] response in
                        if response == nil, retriesOnFailure {
                            self?.recordReconnectFailure()
                            finish(.retry)
                        } else {
                            finish(.finish(response))
                        }
                    }
                }
            },
            completion: completion
        )
    }

    private func enqueueGlobal(
        _ command: ConverterServerCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        commandQueue.enqueue(
            operation: { [weak self] finish in
                guard let self else {
                    finish(.finish(nil))
                    return
                }
                self.sendResolved(command) { response in
                    finish(.finish(response))
                }
            },
            completion: completion
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

    private func openSessionOnServer(completion: ((String?) -> Void)? = nil) {
        remoteObjectProxy { [weak self] proxy in
            guard let self, let proxy else {
                completion?(nil)
                return
            }
            proxy.openSession { sessionID in
                DispatchQueue.main.async {
                    self.sessionID = sessionID
                    self.hasOpenedSession = true
                    self.shouldAttemptReconnect = false
                    self.nextReconnectAttemptDate = .distantPast
                    self.onLog?("ConverterServer session opened: \(sessionID)")
                    completion?(sessionID)
                }
            }
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
        self.connection = nil
        if sessionID != nil || hasOpenedSession {
            shouldAttemptReconnect = true
        }
        if !preservingSession {
            self.sessionID = nil
        }
    }

    private func invalidateConnection() {
        connection?.invalidate()
        resetConnection(preservingSession: false)
    }

    private func recordReconnectFailure() {
        shouldAttemptReconnect = true
        nextReconnectAttemptDate = Date().addingTimeInterval(2)
    }
}
