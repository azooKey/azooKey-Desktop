import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

private final class ConverterSession: SegmentManagerDelegate {
    let manager: SegmentsManager
    private var leftSideContext: String?

    init(manager: SegmentsManager) {
        self.manager = manager
        self.manager.delegate = self
    }

    func setLeftSideContext(_ value: String?) {
        self.leftSideContext = value
    }

    func getLeftSideContext(maxCount: Int) -> String? {
        guard let leftSideContext else {
            return nil
        }
        return String(leftSideContext.suffix(maxCount))
    }
}

private final class ConverterServer: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private var sessions: [String: ConverterSession] = [:]

    func serverInfo(with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        do {
            let info = ConverterServerInfo(
                protocolVersion: ConverterServerProtocol.currentVersion,
                minimumClientProtocolVersion: ConverterServerProtocol.minimumSupportedClientVersion,
                supportedCommands: ConverterServerCommandName.allCases.map(\.rawValue),
                serverKind: "launchd-mach-service",
                buildIdentifier: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            )
            reply(try ConverterServerCodec.encode(info), nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let sessionID = UUID().uuidString
                self.sessions[sessionID] = ConverterSession(manager: Self.makeSegmentsManager())
                reply(sessionID)
            }
        }
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let removed = self.sessions.removeValue(forKey: sessionID) != nil
                reply(removed)
            }
        }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply("ConverterServer: \(message)")
    }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do {
                    let command = try ConverterServerCodec.decodeCommand(from: data)
                    let response = try self.handle(command)
                    reply(try ConverterServerCodec.encode(response), nil)
                } catch {
                    reply(nil, error.localizedDescription as NSString)
                }
            }
        }
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private func handle(_ command: ConverterServerCommand) throws -> ConverterServerResponse {
        switch command {
        case .activate(let sessionID):
            return try withSession(sessionID, inputState: .none) { session in
                session.manager.activate()
                return nil
            }
        case .deactivate(let sessionID):
            return try withSession(sessionID, inputState: .none) { session in
                session.manager.deactivate()
                return nil
            }
        case .snapshot(let sessionID, let inputState):
            return makeResponse(sessionID: sessionID, inputState: inputState.inputState)
        case .stopComposition(let sessionID):
            return try withSession(sessionID, inputState: .none) { session in
                session.manager.stopComposition()
                return nil
            }
        case .insertText(let sessionID, let text, let inputStyle, let leftSideContext):
            return try withSession(sessionID, inputState: .composing) { session in
                session.setLeftSideContext(leftSideContext)
                session.manager.insertAtCursorPosition(text, inputStyle: Self.resolveInputStyle(inputStyle))
                return nil
            }
        case .insertCompositionSeparator(let sessionID, let inputStyle, let skipUpdate):
            return try withSession(sessionID, inputState: .previewing) { session in
                session.manager.insertCompositionSeparator(inputStyle: Self.resolveInputStyle(inputStyle), skipUpdate: skipUpdate)
                return nil
            }
        case .updateCandidates(let sessionID, let requestRichCandidates):
            return try withSession(sessionID, inputState: .selecting) { session in
                session.manager.update(requestRichCandidates: requestRichCandidates)
                return nil
            }
        case .deleteBackward(let sessionID, let count, let leftSideContext):
            return try withSession(sessionID, inputState: .composing) { session in
                session.setLeftSideContext(leftSideContext)
                session.manager.deleteBackwardFromCursorPosition(count: count)
                return nil
            }
        case .editSegment(let sessionID, let count):
            return try withSession(sessionID, inputState: .selecting) { session in
                session.manager.editSegment(count: count)
                return nil
            }
        case .setCandidateWindowVisible(let sessionID, let visible, let inputState):
            return try withSession(sessionID, inputState: inputState.inputState) { session in
                session.manager.requestSetCandidateWindowState(visible: visible)
                return nil
            }
        case .selectNextCandidate(let sessionID):
            return try withSession(sessionID, inputState: .selecting) { session in
                session.manager.requestSelectingNextCandidate()
                return nil
            }
        case .selectPreviousCandidate(let sessionID):
            return try withSession(sessionID, inputState: .selecting) { session in
                session.manager.requestSelectingPrevCandidate()
                return nil
            }
        case .selectCandidate(let sessionID, let index):
            return try withSession(sessionID, inputState: .selecting) { session in
                session.manager.requestSelectingRow(index)
                return nil
            }
        case .resetSelection(let sessionID):
            return try withSession(sessionID, inputState: .composing) { session in
                session.manager.requestResettingSelection()
                return nil
            }
        case .submitSelectedCandidate(let sessionID, let leftSideContext):
            return try withSession(sessionID, inputState: .selecting) { session in
                guard let candidate = session.manager.selectedCandidate else {
                    return nil
                }
                session.manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
                return candidate.text
            }
        case .submitTransformedCandidate(let sessionID, let transform, let inputState, let leftSideContext):
            return try withSession(sessionID, inputState: .selecting) { session in
                let candidate = Self.transformedCandidate(
                    transform,
                    manager: session.manager,
                    inputState: inputState.inputState
                )
                session.manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
                return candidate.text
            }
        case .commitMarkedText(let sessionID, let inputState):
            return try withSession(sessionID, inputState: .none) { session in
                session.manager.commitMarkedText(inputState: inputState.inputState)
            }
        case .forgetMemory(let sessionID):
            return try withSession(sessionID, inputState: .none) { session in
                session.manager.forgetMemory()
                return nil
            }
        }
    }

    @MainActor
    private func withSession(
        _ sessionID: String,
        inputState: InputState,
        body: (ConverterSession) throws -> String?
    ) throws -> ConverterServerResponse {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        let committedText = try body(session)
        return makeResponse(sessionID: sessionID, inputState: inputState, committedText: committedText)
    }

    @MainActor
    private func makeResponse(
        sessionID: String,
        inputState: InputState,
        committedText: String? = nil
    ) -> ConverterServerResponse {
        guard let session = sessions[sessionID] else {
            return ConverterServerResponse(
                sessionID: sessionID,
                committedText: committedText,
                snapshot: .empty
            )
        }
        return ConverterServerResponse(
            sessionID: sessionID,
            committedText: committedText,
            snapshot: snapshot(for: session.manager, inputState: inputState)
        )
    }

    @MainActor
    private func snapshot(for manager: SegmentsManager, inputState: InputState) -> ConverterSessionSnapshot {
        if manager.isEmpty {
            return .empty
        }
        let markedText = ConverterMarkedText(manager.getCurrentMarkedText(inputState: inputState))
        let candidateWindow: ConverterCandidateWindow
        switch manager.getCurrentCandidateWindow(inputState: inputState) {
        case .hidden:
            candidateWindow = .hidden
        case .composing(let candidates, let selectionIndex):
            candidateWindow = .composing(
                manager.makeCandidatePresentations(candidates).map(ConverterCandidatePresentation.init),
                selectionIndex: selectionIndex
            )
        case .selecting(let candidates, let selectionIndex):
            candidateWindow = .selecting(
                manager.makeCandidatePresentations(candidates).map(ConverterCandidatePresentation.init),
                selectionIndex: selectionIndex
            )
        }
        return ConverterSessionSnapshot(
            markedText: markedText,
            candidateWindow: candidateWindow,
            isEmpty: manager.isEmpty,
            convertTarget: manager.convertTarget
        )
    }

    @MainActor
    private static func makeSegmentsManager() -> SegmentsManager {
        CustomInputTableStore.registerIfExists()
        return SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: applicationSupportDirectoryURL(),
            containerURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.azooKeyMacIdentifier),
            context: .init(useZenzai: true, resourcesDirectoryURL: appResourcesDirectoryURL())
        )
    }

    private static func appResourcesDirectoryURL() -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
        }
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    }

    @MainActor
    private static func resolveInputStyle(_ inputStyle: ConverterInputStyle) -> InputStyle {
        if case .tableName(CustomInputTableStore.tableName) = inputStyle,
           !CustomInputTableStore.registerIfExists() {
            return .mapped(id: .defaultRomanToKana)
        }
        return inputStyle.inputStyle
    }

    private static func applicationSupportDirectoryURL() -> URL {
        if #available(macOS 13, *) {
            return URL.applicationSupportDirectory
                .appending(path: "azooKey", directoryHint: .isDirectory)
                .appending(path: "memory", directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("azooKey", isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
    }

    @MainActor
    private static func transformedCandidate(
        _ transform: ConverterCandidateTransform,
        manager: SegmentsManager,
        inputState: InputState
    ) -> Candidate {
        switch transform {
        case .hiragana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toHiragana()
            }
        case .katakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana()
            }
        case .halfWidthKatakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana().applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            }
        case .fullWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: true)!
            }
        case .halfWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            }
        }
    }
}

private enum ConverterServerError: LocalizedError {
    case unknownSession(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession(let sessionID):
            "Unknown converter session: \(sessionID)"
        }
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
