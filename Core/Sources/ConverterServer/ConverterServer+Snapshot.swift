import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

enum ConverterCandidateTransform {
    case hiragana
    case katakana
    case halfWidthKatakana
    case fullWidthRoman
    case halfWidthRoman
}

extension ConverterServer {
    @MainActor
    func makeResponse(
        for session: ConverterSession,
        inputState: InputState,
        handled: Bool = true,
        effects: [ConverterClientEffect] = [],
        settings: [ConverterSettingDescriptor] = [],
        responseInputState: ConverterInputState? = nil
    ) -> ConverterServerResponse {
        ConverterServerResponse(
            handled: handled,
            effects: effects,
            inputState: responseInputState ?? ConverterInputState(inputState),
            inputLanguage: session.inputLanguage,
            settings: settings,
            snapshot: snapshot(for: session, inputState: inputState)
        )
    }

    @MainActor
    func snapshot(for session: ConverterSession, inputState: InputState) -> ConverterSessionSnapshot {
        let manager = session.manager
        if manager.isEmpty, case .unicodeInput = inputState {
            // Unicode input は SegmentsManager の composition を使わず、Server が
            // 所有する inputState 自体を marked text として描画する。
        } else if manager.isEmpty {
            return .empty
        }
        let markedText: ConverterMarkedText
        if inputState == .replaceSuggestion, let candidate = session.selectedReplaceSuggestion {
            markedText = ConverterMarkedText(
                elements: [.init(content: candidate.text, focus: .focused)],
                selectionRange: .init(location: candidate.text.count, length: 0)
            )
        } else {
            markedText = ConverterMarkedText(manager.getCurrentMarkedText(inputState: inputState))
        }
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
        let predictionCandidates: [ConverterPredictionCandidate]
        if inputState == .composing {
            predictionCandidates = SegmentsManager.preferredPredictionCandidates(
                typoCorrectionCandidates: manager.requestTypoCorrectionPredictionCandidates(),
                predictionCandidates: manager.requestPredictionCandidates()
            ).map(ConverterPredictionCandidate.init)
        } else {
            predictionCandidates = []
        }
        return ConverterSessionSnapshot(
            markedText: markedText,
            candidateWindow: candidateWindow,
            predictionCandidates: predictionCandidates,
            replaceSuggestionCandidates: session.replaceSuggestions.map {
                ConverterCandidatePresentation(CandidatePresentation(candidate: $0))
            },
            replaceSuggestionSelectionIndex: session.replaceSuggestionSelectionIndex,
            isEmpty: manager.isEmpty,
            convertTarget: manager.convertTarget
        )
    }

    @MainActor
    static func makeSegmentsManager(kanaKanjiConverter: KanaKanjiConverter) -> SegmentsManager {
        CustomInputTableStore.registerIfExists()
        let containerURL = AppGroup.containerURL()
        let applicationDirectoryURL = AppGroup.memoryDirectoryURL()
        let typoCorrectionDirectoryURL = DebugTypoCorrectionWeights.modelDirectoryURL(
            azooKeyApplicationSupportDirectoryURL: applicationDirectoryURL.deletingLastPathComponent()
        )
        try? FileManager.default.createDirectory(
            at: applicationDirectoryURL,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: typoCorrectionDirectoryURL,
            withIntermediateDirectories: true
        )
        return SegmentsManager(
            kanaKanjiConverter: kanaKanjiConverter,
            applicationDirectoryURL: applicationDirectoryURL,
            containerURL: containerURL,
            context: .init(useZenzai: true, resourcesDirectoryURL: appResourcesDirectoryURL())
        )
    }

    static func appResourcesDirectoryURL() -> URL {
        if let executableURL = Bundle.main.executableURL {
            var directoryURL = executableURL.deletingLastPathComponent()
            while directoryURL.path != "/" {
                if directoryURL.lastPathComponent == "Contents" {
                    return directoryURL.appendingPathComponent("Resources", isDirectory: true)
                }
                directoryURL.deleteLastPathComponent()
            }
        }
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    }

    @MainActor
    static func resolveInputStyle(_ inputStyle: ConverterInputStyle) -> InputStyle {
        if case .tableName(CustomInputTableStore.tableName) = inputStyle,
           !CustomInputTableStore.registerIfExists() {
            return .mapped(id: .defaultRomanToKana)
        }
        return inputStyle.inputStyle
    }

    @MainActor
    static func transformedCandidate(
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
