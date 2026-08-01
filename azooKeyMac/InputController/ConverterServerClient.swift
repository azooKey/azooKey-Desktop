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

final class ConverterServerClient {
    private var connection: NSXPCConnection?
    private var sessionID: String?
    private let syncTimeout: TimeInterval = 0.8
    private var hasOpenedSession = false
    private var shouldAttemptReconnect = false
    private var nextReconnectAttemptDate = Date.distantPast

    var onLog: ((String) -> Void)?
    var hasOpenSession: Bool {
        sessionID != nil
    }
    var canSendOrReconnect: Bool {
        sessionID != nil || !hasOpenedSession || (shouldAttemptReconnect && Date() >= nextReconnectAttemptDate)
    }

    func openSession(completion: ((String?) -> Void)? = nil) {
        if let sessionID {
            completion?(sessionID)
            return
        }
        openSessionOnServer(completion: completion)
    }

    func openSessionSync() -> String? {
        if let sessionID {
            return sessionID
        }
        let sessionID = waitForResult(timeout: syncTimeout) { [weak self] complete in
            self?.openSessionOnServer(completion: complete)
        }
        if sessionID == nil {
            recordReconnectFailure()
        }
        return sessionID
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
        sendResolved(.shutdown) { [weak self] response in
            self?.invalidateConnection()
            completion(response != nil)
        }
    }

    func send(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        openSession { [weak self] sessionID in
            guard let self, let sessionID else {
                completion(nil)
                return
            }
            self.sendResolved(
                .session(sessionID: sessionID, command: commandBuilder(sessionID)),
                completion: completion
            )
        }
    }

    func sendSync(_ commandBuilder: (String) -> ConverterSessionCommand) -> ConverterServerResponse? {
        guard let sessionID = openSessionSync() else {
            return nil
        }
        return sendResolvedSync(.session(sessionID: sessionID, command: commandBuilder(sessionID)))
    }

    func sendIfSessionOpenSync(_ commandBuilder: (String) -> ConverterSessionCommand) -> ConverterServerResponse? {
        guard let sessionID else {
            return nil
        }
        return sendResolvedSync(.session(sessionID: sessionID, command: commandBuilder(sessionID)))
    }

    func sendIfSessionOpen(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        guard let sessionID else {
            completion(nil)
            return
        }
        sendResolved(.session(sessionID: sessionID, command: commandBuilder(sessionID)), completion: completion)
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

    private func openSessionOnServer(completion: ((String?) -> Void)? = nil) {
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
    }

    private func invalidateConnection() {
        connection?.invalidate()
        resetConnection()
    }

    private func recordReconnectFailure() {
        shouldAttemptReconnect = true
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
