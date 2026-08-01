import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@MainActor
@Suite("Synchronous local input session")
struct InputSessionTests {
    @Test func japaneseKeystrokesAreConsumedAndImmediatelyUpdateMarkedText() {
        let session = self.makeSession()

        for event in [self.keyEvent("k", keyCode: 40), self.keyEvent("a", keyCode: 0)] {
            let result = self.handle(event, with: session)

            #expect(result.handled)
            #expect(self.insertedTexts(in: result).isEmpty)
            #expect(!session.segmentsManager.convertTarget.isEmpty)
        }

        #expect(session.inputState == .composing)
        #expect(session.segmentsManager.convertTarget == "か")
        let markedText = session.segmentsManager.getCurrentMarkedText(inputState: session.inputState)
        #expect(markedText.map(\.content).joined() == "か")
    }

    @Test func consecutiveKeystrokesNeverFallThroughWhileComposing() {
        let session = self.makeSession()
        let events = [
            self.keyEvent("k", keyCode: 40),
            self.keyEvent("a", keyCode: 0),
            self.keyEvent("n", keyCode: 45),
            self.keyEvent("j", keyCode: 38),
            self.keyEvent("i", keyCode: 34)
        ]

        let results = events.map { self.handle($0, with: session) }

        #expect(results.allSatisfy { $0.handled })
        #expect(results.flatMap(self.insertedTexts(in:)).isEmpty)
        #expect(session.inputState == .composing)
        #expect(session.segmentsManager.convertTarget == "かんじ")
    }

    @Test func enterCommitsCompositionAsAnInsertEffect() {
        let session = self.makeSession()
        _ = self.handle(self.keyEvent("k", keyCode: 40), with: session)
        _ = self.handle(self.keyEvent("a", keyCode: 0), with: session)

        let result = self.handle(
            KeyEventCore(
                modifierFlags: [],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                keyCode: 0x24
            ),
            with: session
        )

        #expect(result.handled)
        #expect(self.insertedTexts(in: result) == ["か"])
        #expect(session.inputState == .none)
        #expect(session.segmentsManager.isEmpty)
    }

    @Test func unknownKeyInEmptyStateFallsThrough() {
        let session = self.makeSession()
        let event = KeyEventCore(
            modifierFlags: [],
            characters: nil,
            charactersIgnoringModifiers: nil,
            keyCode: 0x73
        )

        let result = self.handle(event, with: session)

        #expect(!result.handled)
        #expect(session.inputState == .none)
        #expect(session.segmentsManager.isEmpty)
    }

    private func makeSession() -> InputSession {
        let segmentsManager = SegmentsManager(
            kanaKanjiConverter: .withDefaultDictionary(),
            applicationDirectoryURL: FileManager.default.temporaryDirectory,
            containerURL: nil,
            context: .init(useZenzai: false)
        )
        return InputSession(segmentsManager: segmentsManager)
    }

    private func keyEvent(_ character: String, keyCode: UInt16) -> KeyEventCore {
        KeyEventCore(
            modifierFlags: [],
            characters: character,
            charactersIgnoringModifiers: character,
            keyCode: keyCode
        )
    }

    private func handle(_ event: KeyEventCore, with session: InputSession) -> InputSession.Result {
        session.handle(
            eventCore: event,
            userAction: UserAction.getUserAction(eventCore: event, inputLanguage: session.inputLanguage),
            configuration: .init(
                inputStyle: .roman2kana,
                liveConversionEnabled: false,
                enableDebugWindow: false,
                enableSuggestion: false
            )
        )
    }

    private func insertedTexts(in result: InputSession.Result) -> [String] {
        result.effects.compactMap { effect in
            guard case .insertText(let text) = effect else {
                return nil
            }
            return text
        }
    }
}
