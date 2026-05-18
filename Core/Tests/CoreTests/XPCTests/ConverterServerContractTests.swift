import Core
import Foundation
import Testing

private func makeSnapshot(candidateWindow: ConverterCandidateWindow) -> ConverterSessionSnapshot {
    ConverterSessionSnapshot(
        markedText: ConverterSessionSnapshot.empty.markedText,
        candidateWindow: candidateWindow,
        isEmpty: false,
        convertTarget: "あい"
    )
}

@Test func converterServerEmptySnapshotHasNoVisibleComposition() {
    let snapshot = ConverterSessionSnapshot.empty

    #expect(snapshot.isEmpty)
    #expect(snapshot.convertTarget.isEmpty)
    #expect(snapshot.markedText.elements.isEmpty)
    #expect(snapshot.markedText.selectionRange.nsRange.location == NSNotFound)
    #expect(snapshot.markedText.selectionRange.nsRange.length == NSNotFound)
    #expect(snapshot.inputStateFromCandidateWindow == nil)

    guard case .hidden = snapshot.candidateWindow else {
        Issue.record("Expected hidden candidate window, got \(snapshot.candidateWindow)")
        return
    }
}

@Test func converterServerSnapshotCandidateWindowRestoresClientInputState() {
    let selecting = makeSnapshot(candidateWindow: .selecting([], selectionIndex: 0))
    #expect(selecting.inputStateFromCandidateWindow == .selecting)

    let composing = makeSnapshot(candidateWindow: .composing([], selectionIndex: nil))
    #expect(composing.inputStateFromCandidateWindow == .composing)

    let hidden = makeSnapshot(candidateWindow: .hidden)
    #expect(hidden.inputStateFromCandidateWindow == nil)
}

@Test func converterServerEditSegmentCommandCodableShape() throws {
    let expectedJSON = #"{"editSegment":{"sessionID":"session-1","count":-1}}"#
    let command = try ConverterServerCodec.decodeCommand(from: Data(expectedJSON.utf8))

    guard case .editSegment(let sessionID, let count) = command else {
        Issue.record("Expected editSegment command, got \(command)")
        return
    }
    #expect(sessionID == "session-1")
    #expect(count == -1)
    #expect(command.commandName == .editSegment)

    let roundTrip = try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(command))
    guard case .editSegment(let roundTripSessionID, let roundTripCount) = roundTrip else {
        Issue.record("Expected editSegment command after round trip, got \(roundTrip)")
        return
    }
    #expect(roundTripSessionID == "session-1")
    #expect(roundTripCount == -1)
}

@Test func converterServerInfoAdvertisesAllKnownCommands() {
    let info = ConverterServerInfo(
        protocolVersion: ConverterServerProtocol.currentVersion,
        minimumClientProtocolVersion: ConverterServerProtocol.minimumSupportedClientVersion,
        supportedCommands: ConverterServerCommandName.allCases.map(\.rawValue),
        serverKind: "test"
    )

    #expect(info.isCompatibleWithClient(protocolVersion: ConverterServerProtocol.currentVersion))
    for commandName in ConverterServerCommandName.allCases {
        #expect(info.supports(commandName))
    }
}
