import Core
import Foundation

/// 接続の終了後に届く要求を実行せず、その接続が残した session を回収する。
final class ConverterServerConnection: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private let server: ConverterServer
    private let owner = UUID()
    private let cleanupDelay: TimeInterval
    private let lock = NSLock()
    private var closed = false

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func markClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            return false
        }
        closed = true
        return true
    }

    init(server: ConverterServer, cleanupDelay: TimeInterval = 5) {
        self.server = server
        self.cleanupDelay = cleanupDelay
    }

    func invalidate() {
        guard markClosed() else {
            return
        }
        Task { @MainActor in
            // 旧Clientの再接続・同一sessionへの再送を短時間だけ許容する。
            // 新接続が所有権を取得したsessionは、古い接続のcleanupでは削除しない。
            DispatchQueue.main.asyncAfter(deadline: .now() + self.cleanupDelay) {
                self.server.removeSessions(ownedBy: self.owner)
            }
        }
    }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        Task(priority: .userInitiated) { @MainActor in
            guard !self.isClosed else {
                reply(nil, "ConverterServer connection is closed")
                return
            }
            do {
                let command = try ConverterServerCodec.decodeCommand(from: data)
                let response = try await self.server.execute(command, owner: self.owner)
                reply(try ConverterServerCodec.encode(response), nil)
            } catch {
                reply(nil, error.localizedDescription as NSString)
            }
        }
    }

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        Task { @MainActor in
            guard !self.isClosed else {
                reply("")
                return
            }
            let id = UUID().uuidString
            _ = try? await self.server.execute(.openSession(sessionID: id, command: .composition(.snapshot)), owner: self.owner)
            reply(id)
        }
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        Task { @MainActor in reply(self.server.removeSession(sessionID)) }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply("ConverterServer: \(message)")
    }
}
