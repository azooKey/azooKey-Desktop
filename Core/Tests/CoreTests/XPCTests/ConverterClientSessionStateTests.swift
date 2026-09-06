import Core
import Testing

private let sessionConfig = ConverterSessionConfig(
    aiBackendPreference: .off,
    openAIModelName: "model",
    openAIEndpoint: "https://example.com",
    openAIAPIKey: .init(""),
    includeContextInAITransform: false
)

@Test(arguments: [InputLanguage.japanese, .english])
func activationUsesModeChangedAfterActivate(language: InputLanguage) {
    var state = ConverterClientSessionState()
    state.inputLanguage = language == .japanese ? .english : .japanese
    state.activate()
    state.inputLanguage = language
    #expect(state.takeActivation(config: sessionConfig)?.inputLanguage == language)
    #expect(state.takeActivation(config: sessionConfig) == nil)
}

@Test(arguments: [InputLanguage.japanese, .english])
func activationUsesModeChangedBeforeActivate(language: InputLanguage) {
    var state = ConverterClientSessionState()
    state.inputLanguage = language
    state.activate()
    #expect(state.takeActivation(config: sessionConfig)?.inputLanguage == language)
}

@Test func resetAndReactivationUseLatestModeAndConfiguration() {
    var state = ConverterClientSessionState()
    state.activate()
    _ = state.takeActivation(config: sessionConfig)
    state.connectionDidReset()
    state.inputLanguage = .english
    var updated = sessionConfig
    updated.openAIModelName = "updated"
    #expect(state.takeActivation(config: updated) == .init(config: updated, inputLanguage: .english))
    state.deactivate()
    #expect(!state.isActive)
    state.connectionDidReset()
    #expect(!state.isActive)
    state.inputLanguage = .japanese
    state.activate()
    #expect(state.isActive)
    #expect(state.takeActivation(config: updated)?.inputLanguage == .japanese)
}

@Test func ordinaryKeysDoNotReadActivationConfigurationAgain() {
    var state = ConverterClientSessionState()
    var reads = 0
    func readConfig() -> ConverterSessionConfig {
        reads += 1
        return sessionConfig
    }
    _ = state.takeActivation(config: readConfig())
    _ = state.takeActivation(config: readConfig())
    #expect(reads == 1)
}
