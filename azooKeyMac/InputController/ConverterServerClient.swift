import Core
import Foundation

@objc protocol ConverterServerXPCProtocol {
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

@MainActor
final class ConverterServerClient {
    private enum Command {
        case session((String) -> ConverterSessionCommand)
        case global(ConverterServerCommand)
    }

    private enum Reply: Sendable {
        case response(Data)
        case failure(String)
    }

    private struct PendingCommand {
        let id = UUID()
        let command: Command
        let timeout: TimeInterval
        let completion: (ConverterServerResponse?) -> Void
    }

    private struct ActiveCommand {
        let id: UUID
        let reply: DeadlineReply<Reply>
        let openingSessionID: String?
    }

    // 通常の変換が遅いだけでキーを途中放棄しない長さを取る。
    private let keyEventTimeout: TimeInterval
    private let commandTimeout: TimeInterval
    private let connectionFactory: @Sendable () -> NSXPCConnection
    private var connection: NSXPCConnection?
    private var sessionID: String?
    private var abandonedSessionIDs: [String] = []
    private var pendingCommands: [PendingCommand] = []
    private var activeCommand: ActiveCommand?

    var onLog: ((String) -> Void)?
    var onSessionReset: (() -> Void)?

    nonisolated init(
        keyEventTimeout: TimeInterval = 30,
        commandTimeout: TimeInterval = 1,
        connectionFactory: @escaping @Sendable () -> NSXPCConnection = {
            NSXPCConnection(machServiceName: "dev.ensan.inputmethod.azooKeyMac.ConverterServer", options: [])
        }
    ) {
        self.keyEventTimeout = keyEventTimeout
        self.commandTimeout = commandTimeout
        self.connectionFactory = connectionFactory
    }

    func listSettings(
        capabilities: ConverterSettingClientCapabilities,
        completion: @escaping ([ConverterSettingDescriptor]?) -> Void
    ) {
        send({ _ in .settings(.list(capabilities: capabilities)) }, completion: { completion($0?.settings) })
    }

    func updateSetting(key: String, value: ConverterSettingValue, completion: @escaping (Bool) -> Void) {
        send({ _ in .settings(.update(key: key, value: value)) }, completion: { completion($0 != nil) })
    }

    func restartServer(completion: @escaping (Bool) -> Void) {
        enqueue(.global(.shutdown), timeout: commandTimeout) { [weak self] response in
            self?.resetSession()
            completion(response != nil)
        }
    }

    func synchronizeUserDictionary(forceExport: Bool, completion: @escaping (Bool) -> Void) {
        enqueue(.global(.maintenance(.synchronizeUserDictionary(forceExport: forceExport))), timeout: commandTimeout) {
            completion($0 != nil)
        }
    }

    func resetLearningData(completion: @escaping (Bool) -> Void) {
        enqueue(.global(.maintenance(.resetLearningData)), timeout: commandTimeout) { completion($0 != nil) }
    }

    func send(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        enqueue(.session(commandBuilder), timeout: commandTimeout, completion: completion)
    }

    func sendIfSessionOpen(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        guard sessionID != nil else {
            completion(nil)
            return
        }
        send(commandBuilder, completion: completion)
    }

    /// 応答を受け取る XPC キューはブロックしない。呼び出し元だけが期限付きで待つ。
    func sendKeyEvent(_ request: ConverterKeyEventRequest) -> ConverterServerResponse? {
        sendSynchronously { _ in .handleKeyEvent(request) }
    }

    func sendSynchronously(
        _ commandBuilder: @escaping (String) -> ConverterSessionCommand,
        onlyIfSessionOpen: Bool = false
    ) -> ConverterServerResponse? {
        flushPendingCommands()
        if onlyIfSessionOpen && sessionID == nil {
            return nil
        }
        var response: ConverterServerResponse?
        enqueue(.session(commandBuilder), timeout: keyEventTimeout) { response = $0 }
        flushPendingCommands()
        return response
    }

    /// 先行するモード変更・候補選択等を反映してから次のキーを判定する。
    /// completion もここで実行し、古い応答が後から UI を巻き戻すことを防ぐ。
    func flushPendingCommands() {
        while let activeCommand {
            finishCommand(id: activeCommand.id)
        }
    }

    private func enqueue(
        _ command: Command,
        timeout: TimeInterval,
        completion: @escaping (ConverterServerResponse?) -> Void
    ) {
        pendingCommands.append(.init(command: command, timeout: timeout, completion: completion))
        startNextCommand()
    }

    private func startNextCommand() {
        guard activeCommand == nil, let pending = pendingCommands.first else {
            return
        }
        let command: ConverterServerCommand
        var openingSessionID: String?
        switch pending.command {
        case .session(let builder):
            if let sessionID {
                command = .session(sessionID: sessionID, command: builder(sessionID))
            } else {
                let newID = UUID().uuidString
                openingSessionID = newID
                command = .openSession(sessionID: newID, command: builder(newID))
            }
        case .global(let global):
            command = global
        }

        let reply = DeadlineReply<Reply>(timeout: pending.timeout)
        let id = pending.id
        activeCommand = .init(id: id, reply: reply, openingSessionID: openingSessionID)
        // reply の保存と signal は XPC の返信キューで行う。MainActor への移動はその後。
        let complete: @Sendable (Reply) -> Void = { [weak self] result in
            reply.complete(result)
            DispatchQueue.main.async { self?.finishCommand(id: id) }
        }
        do {
            let data = try ConverterServerCodec.encode(command)
            let connection = ensureConnection()
            if let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                complete(.failure(error.localizedDescription))
            }) as? ConverterServerXPCProtocol {
                proxy.handleCommand(data) { data, error in
                    if let error {
                        complete(.failure(String(error)))
                    } else if let data {
                        complete(.response(data))
                    } else {
                        complete(.failure("Empty ConverterServer response"))
                    }
                }
            } else {
                complete(.failure("Failed to create ConverterServer proxy"))
            }
        } catch {
            complete(.failure(error.localizedDescription))
        }
        DispatchQueue.main.asyncAfter(deadline: reply.deadline) { [weak self] in
            self?.finishCommand(id: id)
        }
    }

    private func finishCommand(id: UUID) {
        guard let active = activeCommand, active.id == id else {
            return
        }
        let result = active.reply.wait()
        let pending = pendingCommands.removeFirst()
        activeCommand = nil
        var response: ConverterServerResponse?
        switch result {
        case .response(let data):
            do {
                response = try ConverterServerCodec.decodeResponse(from: data)
            } catch {
                onLog?("ConverterServer decode failed: \(error.localizedDescription)")
            }
        case .failure(let message):
            onLog?("ConverterServer command failed: \(message)")
        case nil:
            onLog?("ConverterServer command timed out")
        }
        if response != nil {
            if let openingSessionID = active.openingSessionID {
                sessionID = openingSessionID
            }
            pending.completion(response)
            startNextCommand()
        } else {
            // Server が処理済みかは不明。再送せず、新しい session へ切り替える。
            let abandoned = pendingCommands
            pendingCommands.removeAll()
            resetSession(openingSessionID: active.openingSessionID)
            pending.completion(nil)
            for command in abandoned {
                command.completion(nil)
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = connectionFactory()
        connection.remoteObjectInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.resume()
        self.connection = connection
        // 切断前の計算は継続している場合がある。新しい接続で旧 session を回収する。
        if !abandonedSessionIDs.isEmpty,
           let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? ConverterServerXPCProtocol {
            for id in abandonedSessionIDs {
                proxy.closeSession(id) { _ in }
            }
            abandonedSessionIDs.removeAll()
        }
        return connection
    }

    private func resetSession(openingSessionID: String? = nil) {
        // 切断は Server の計算をキャンセルしない。同じ session を使うと、
        // 時間切れになったキーが次回の候補へ混入するので再利用しない。
        if let id = sessionID ?? openingSessionID {
            abandonedSessionIDs.append(id)
        }
        sessionID = nil
        connection?.invalidate()
        connection = nil
        onSessionReset?()
    }
}
