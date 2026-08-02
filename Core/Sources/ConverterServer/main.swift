import Core
import Darwin
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

private enum ConverterServerXPC {
    static let machServiceName = "dev.ensan.inputmethod.azooKeyMac.ConverterServer"
}

@objc private protocol ConverterServerXPCProtocol {
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

final class ConverterServer: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private static let learningDataCommitDelay: TimeInterval = 2

    private var sessions: [String: ConverterSession] = [:]
    private let kanaKanjiConverter = KanaKanjiConverter.withDefaultDictionary()
    private let learningDataCommitScheduler = DebouncedActionScheduler()

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let sessionID = UUID().uuidString
                self.createSessionIfNeeded(sessionID)
                reply(sessionID)
            }
        }
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let session = self.sessions.removeValue(forKey: sessionID)
                if let session {
                    self.kanaKanjiConverter.removeSession(session.conversionSessionID)
                }
                let removed = session != nil
                reply(removed)
            }
        }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply("ConverterServer: \(message)")
    }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        // キー入力の応答はユーザー操作のクリティカルパスなので、システム負荷が高い時も
        // utility/background work より先に実行される優先度で Server actor へ渡す。
        Task(priority: .userInitiated) { @MainActor in
            do {
                let command = try ConverterServerCodec.decodeCommand(from: data)
                let response = try await self.handle(command)
                self.learningDataCommitScheduler.postponeIfScheduled(
                    after: Self.learningDataCommitDelay
                )
                reply(try ConverterServerCodec.encode(response), nil)
            } catch {
                self.learningDataCommitScheduler.postponeIfScheduled(
                    after: Self.learningDataCommitDelay
                )
                reply(nil, error.localizedDescription as NSString)
            }
        }
    }

    @MainActor
    private func handle(_ command: ConverterServerCommand) async throws -> ConverterServerResponse {
        switch command {
        case .shutdown:
            Self.scheduleShutdown()
            return ConverterServerResponse(snapshot: .empty)
        case .maintenance(let command):
            return try handle(command)
        case .openSession(let sessionID, let command):
            createSessionIfNeeded(sessionID)
            return try await handle(command, sessionID: sessionID)
        case .session(let sessionID, let command):
            return try await handle(command, sessionID: sessionID)
        }
    }

    @MainActor
    private func createSessionIfNeeded(_ sessionID: String) {
        guard sessions[sessionID] == nil else {
            return
        }
        let conversionSessionID = kanaKanjiConverter.createSession()
        sessions[sessionID] = ConverterSession(
            manager: Self.makeSegmentsManager(kanaKanjiConverter: kanaKanjiConverter),
            conversionSessionID: conversionSessionID
        )
    }

    @MainActor
    private func handle(_ command: ConverterMaintenanceCommand) throws -> ConverterServerResponse {
        switch command {
        case .synchronizeUserDictionary(let forceExport):
            let memoryDirectoryURL = AppGroup.memoryDirectoryURL()
            if forceExport || !CompiledUserDictionaryStore.hasExportedDictionary(memoryDirectoryURL: memoryDirectoryURL) {
                try CompiledUserDictionaryStore.exportCurrentDictionaries(memoryDirectoryURL: memoryDirectoryURL)
            }
            kanaKanjiConverter.updateUserDictionaryURL(
                CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: memoryDirectoryURL),
                forceReload: true
            )
        case .resetLearningData:
            kanaKanjiConverter.resetMemory()
        }
        return ConverterServerResponse(snapshot: .empty)
    }

    @MainActor
    private func handle(_ command: ConverterSessionCommand, sessionID: String) async throws -> ConverterServerResponse {
        let session = try getSession(sessionID)
        switch command {
        case .lifecycle(let command):
            return try withConverterSession(session) {
                handle(command, session: session)
            }
        case .settings(let command):
            return try withConverterSession(session) {
                try handle(command, session: session)
            }
        case .updateConfig(let config):
            return try withConverterSession(session) {
                session.config = config
                return makeResponse(for: session, inputState: .none)
            }
        case .handleKeyEvent(let request):
            return try withConverterSession(session) {
                try handleKeyEvent(sessionID: sessionID, request: request)
            }
        case .composition(let command):
            return try withConverterSession(session) {
                handle(command, session: session)
            }
        case .candidate(let command):
            return try withConverterSession(session) {
                handle(command, session: session)
            }
        case .replaceSuggestion(let command):
            return try await handle(command, session: session)
        }
    }

    @MainActor
    private func withConverterSession<Result>(
        _ session: ConverterSession,
        operation: () throws -> Result
    ) throws -> Result {
        try kanaKanjiConverter.withSession(session.conversionSessionID, operation: operation)
    }

    @MainActor
    private func handle(
        _ command: ConverterSessionLifecycleCommand,
        session: ConverterSession
    ) -> ConverterServerResponse {
        switch command {
        case .activate:
            session.manager.activate()
            return makeResponse(for: session, inputState: session.inputState)
        case .deactivate:
            // アプリ切替直後のキー入力を、学習データの同期I/Oで塞がない。
            // 共有Converterはプロセス内に残るため、永続化だけ入力のアイドル時まで遅延できる。
            session.manager.deactivate(flushLearningData: false)
            scheduleLearningDataCommit()
            session.inputState = .none
            session.clearReplaceSuggestions()
            return makeResponse(for: session, inputState: session.inputState)
        case .synchronizeInputLanguage(let language):
            session.inputLanguage = language
            if language == .english {
                session.manager.stopJapaneseInput()
            }
            return makeResponse(
                for: session,
                inputState: session.inputState
            )
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterSettingsCommand,
        session: ConverterSession
    ) throws -> ConverterServerResponse {
        switch command {
        case .list(let capabilities):
            return makeResponse(
                for: session,
                inputState: .none,
                settings: Self.makeSettingDescriptors(capabilities: capabilities)
            )
        case .update(let key, let value):
            try Self.updateSetting(key: key, value: value)
            return makeResponse(for: session, inputState: .none)
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterCompositionCommand,
        session: ConverterSession
    ) -> ConverterServerResponse {
        switch command {
        case .snapshot:
            return makeResponse(for: session, inputState: session.inputState)
        case .stopComposition:
            session.manager.stopComposition()
            session.inputState = .none
            return makeResponse(for: session, inputState: session.inputState)
        case .forgetMemory:
            session.manager.forgetMemory()
            return makeResponse(for: session, inputState: session.inputState)
        case .commit:
            let text = session.manager.commitMarkedText(inputState: session.inputState)
            let effects: [ConverterClientEffect] = text.isEmpty ? [] : [.insertText(text)]
            session.inputState = .none
            return makeResponse(
                for: session,
                inputState: session.inputState,
                effects: effects,
                responseInputState: ConverterInputState.none
            )
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterCandidateCommand,
        session: ConverterSession
    ) -> ConverterServerResponse {
        switch command {
        case .selectCandidate(let index):
            session.manager.requestSelectingRow(index)
            session.inputState = .selecting
            return makeResponse(for: session, inputState: session.inputState)
        case .submitSelectedCandidate(let context):
            session.setContext(context)
            var effects: [ConverterClientEffect] = []
            submitSelectedCandidate(
                manager: session.manager,
                leftSideContext: session.conversionLeftSideContext(),
                effects: &effects
            )
            let nextInputState: InputState = session.manager.isEmpty ? .none : .previewing
            session.inputState = nextInputState
            return makeResponse(
                for: session,
                inputState: nextInputState,
                effects: effects,
                responseInputState: ConverterInputState(nextInputState)
            )
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterReplaceSuggestionCommand,
        session: ConverterSession
    ) async throws -> ConverterServerResponse {
        switch command {
        case .request(let context):
            session.setContext(context)
            try await requestReplaceSuggestion(session: session)
            return try withConverterSession(session) {
                session.inputState = .replaceSuggestion
                return makeResponse(
                    for: session,
                    inputState: session.inputState,
                    responseInputState: .replaceSuggestion
                )
            }
        case .selectReplaceSuggestionCandidate(let index):
            return try withConverterSession(session) {
                session.selectReplaceSuggestion(at: index)
                session.inputState = .replaceSuggestion
                return makeResponse(
                    for: session,
                    inputState: session.inputState,
                    responseInputState: .replaceSuggestion
                )
            }
        case .submitSelectedReplaceSuggestion:
            return try withConverterSession(session) {
                var effects: [ConverterClientEffect] = []
                let didSubmit = submitSelectedReplaceSuggestion(session: session, effects: &effects)
                let nextInputState: InputState = didSubmit ? .none : .replaceSuggestion
                session.inputState = nextInputState
                return makeResponse(
                    for: session,
                    inputState: nextInputState,
                    effects: effects,
                    responseInputState: ConverterInputState(nextInputState)
                )
            }
        }
    }

    private static func scheduleShutdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(EXIT_SUCCESS)
        }
    }

    @MainActor
    private func scheduleLearningDataCommit() {
        learningDataCommitScheduler.schedule(after: Self.learningDataCommitDelay) { [weak self] in
            self?.kanaKanjiConverter.commitUpdateLearningData()
        }
    }

    @MainActor
    func getSession(_ sessionID: String) throws -> ConverterSession {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        return session
    }

}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let server = ConverterServer()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = server
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: ConverterServerXPC.machServiceName)
private let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
