import Core
import Foundation

private enum ConverterServerXPC {
    static let machServiceName = "dev.ensan.inputmethod.azooKeyMac.ConverterServer"
}

@objc private protocol ConverterServerXPCProtocol {
    func serverInfo(with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

final class ConverterServerClient {
    private var connection: NSXPCConnection?
    private var sessionID: String?
    private var serverInfo: ConverterServerInfo?
    private let syncTimeout: TimeInterval = 0.8
    private var hasOpenedSession = false
    private var shouldAttemptReconnect = false
    private var nextReconnectAttemptDate = Date.distantPast

    var onLog: ((String) -> Void)?
    var hasOpenSession: Bool {
        sessionID != nil
    }
    var canSendOrReconnect: Bool {
        sessionID != nil || (shouldAttemptReconnect && Date() >= nextReconnectAttemptDate)
    }

    func openSession(completion: ((String?) -> Void)? = nil) {
        if let sessionID {
            completion?(sessionID)
            return
        }
        refreshServerInfo { [weak self] info in
            guard let self, let info, self.isCompatible(info) else {
                completion?(nil)
                return
            }
            self.openCompatibleSession(completion: completion)
        }
    }

    func openSessionSync() -> String? {
        if let sessionID {
            return sessionID
        }
        guard let info = serverInfoSync(), isCompatible(info) else {
            recordReconnectFailure()
            return nil
        }
        let sessionID = waitForResult(timeout: syncTimeout) { [weak self] complete in
            self?.openCompatibleSession(completion: complete)
        }
        if sessionID == nil {
            recordReconnectFailure()
        }
        return sessionID
    }

    func refreshServerInfo(completion: @escaping (ConverterServerInfo?) -> Void) {
        if let serverInfo {
            completion(serverInfo)
            return
        }
        remoteObjectProxy { [weak self] proxy in
            guard let self, let proxy else {
                completion(nil)
                return
            }
            proxy.serverInfo { data, errorMessage in
                if let errorMessage {
                    self.onLog?("ConverterServer info failed: \(errorMessage)")
                    completion(nil)
                    return
                }
                guard let data, let info = try? ConverterServerCodec.decodeServerInfo(from: data) else {
                    self.onLog?("ConverterServer info decode failed")
                    completion(nil)
                    return
                }
                self.serverInfo = info
                self.onLog?("ConverterServer protocol v\(info.protocolVersion), kind=\(info.serverKind)")
                completion(info)
            }
        }
    }

    func closeSession() {
        guard let sessionID else {
            invalidateConnection()
            return
        }
        remoteObjectProxy { [weak self] proxy in
            proxy?.closeSession(sessionID) { _ in
                self?.invalidateConnection()
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

    func send(
        _ commandBuilder: @escaping (String) -> ConverterServerCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        openSession { [weak self] sessionID in
            guard let self, let sessionID else {
                completion(nil)
                return
            }
            self.sendResolved(commandBuilder(sessionID), completion: completion)
        }
    }

    func sendSync(_ commandBuilder: (String) -> ConverterServerCommand) -> ConverterServerResponse? {
        guard let sessionID = openSessionSync() else {
            return nil
        }
        let command = commandBuilder(sessionID)
        guard supports(command) else {
            onLog?("ConverterServer command unsupported: \(command.commandName.rawValue)")
            return nil
        }
        return sendResolvedSync(command)
    }

    func sendIfSessionOpenSync(_ commandBuilder: (String) -> ConverterServerCommand) -> ConverterServerResponse? {
        guard let sessionID else {
            return nil
        }
        let command = commandBuilder(sessionID)
        guard supports(command) else {
            onLog?("ConverterServer command unsupported: \(command.commandName.rawValue)")
            return nil
        }
        return sendResolvedSync(command)
    }

    func sendIfSessionOpen(
        _ commandBuilder: @escaping (String) -> ConverterServerCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        guard let sessionID else {
            completion(nil)
            return
        }
        sendResolved(commandBuilder(sessionID), completion: completion)
    }

    private func remoteObjectProxy(completion: @escaping (ConverterServerXPCProtocol?) -> Void) {
        let connection = ensureConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.onLog?("ConverterServer XPC error: \(error.localizedDescription)")
            self?.resetConnection()
            completion(nil)
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
        guard supports(command) else {
            onLog?("ConverterServer command unsupported: \(command.commandName.rawValue)")
            completion(nil)
            return
        }
        do {
            let data = try ConverterServerCodec.encode(command)
            self.remoteObjectProxy { proxy in
                guard let proxy else {
                    completion(nil)
                    return
                }
                proxy.handleCommand(data) { [weak self] responseData, errorMessage in
                    if let errorMessage {
                        self?.onLog?("ConverterServer command failed: \(errorMessage)")
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
        } catch {
            self.onLog?("ConverterServer encode failed: \(error.localizedDescription)")
            completion(nil)
        }
    }

    private func openCompatibleSession(completion: ((String?) -> Void)? = nil) {
        remoteObjectProxy { [weak self] proxy in
            guard let self, let proxy else {
                completion?(nil)
                return
            }
            proxy.openSession { sessionID in
                self.sessionID = sessionID
                self.hasOpenedSession = true
                self.shouldAttemptReconnect = false
                self.nextReconnectAttemptDate = .distantPast
                self.onLog?("ConverterServer session opened: \(sessionID)")
                completion?(sessionID)
            }
        }
    }

    private func serverInfoSync() -> ConverterServerInfo? {
        if let serverInfo {
            return serverInfo
        }
        return waitForResult(timeout: syncTimeout) { [weak self] complete in
            self?.refreshServerInfo(completion: complete)
        }
    }

    private func sendResolvedSync(_ command: ConverterServerCommand) -> ConverterServerResponse? {
        do {
            let data = try ConverterServerCodec.encode(command)
            return waitForResult(timeout: syncTimeout) { [weak self] complete in
                self?.remoteObjectProxy { proxy in
                    guard let proxy else {
                        complete(nil)
                        return
                    }
                    proxy.handleCommand(data) { responseData, errorMessage in
                        if let errorMessage {
                            self?.onLog?("ConverterServer command failed: \(errorMessage)")
                            complete(nil)
                            return
                        }
                        guard let responseData else {
                            complete(nil)
                            return
                        }
                        complete(try? ConverterServerCodec.decodeResponse(from: responseData))
                    }
                }
            }
        } catch {
            onLog?("ConverterServer encode failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func isCompatible(_ info: ConverterServerInfo) -> Bool {
        guard info.isCompatibleWithClient(protocolVersion: ConverterServerProtocol.currentVersion) else {
            onLog?(
                "ConverterServer protocol incompatible: server min client v\(info.minimumClientProtocolVersion), client v\(ConverterServerProtocol.currentVersion)"
            )
            return false
        }
        return true
    }

    private func supports(_ command: ConverterServerCommand) -> Bool {
        guard let serverInfo else {
            return false
        }
        return serverInfo.supports(command.commandName)
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = NSXPCConnection(machServiceName: ConverterServerXPC.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            self?.onLog?("ConverterServer connection interrupted")
            self?.resetConnection()
        }
        connection.invalidationHandler = { [weak self] in
            self?.onLog?("ConverterServer connection invalidated")
            self?.resetConnection()
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func resetConnection() {
        self.connection = nil
        if sessionID != nil || hasOpenedSession {
            shouldAttemptReconnect = true
        }
        self.sessionID = nil
        self.serverInfo = nil
    }

    private func invalidateConnection() {
        connection?.invalidate()
        resetConnection()
    }

    private func recordReconnectFailure() {
        guard shouldAttemptReconnect else {
            return
        }
        nextReconnectAttemptDate = Date().addingTimeInterval(2)
    }
}

private final class SyncResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ value: Value?) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> Value? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return value
    }
}

private func waitForResult<Value>(
    timeout: TimeInterval,
    start: (@escaping @Sendable (Value?) -> Void) -> Void
) -> Value? {
    let semaphore = DispatchSemaphore(value: 0)
    let result = SyncResult<Value>()
    start { value in
        result.set(value)
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + timeout) == .success else {
        return nil
    }
    return result.get()
}
