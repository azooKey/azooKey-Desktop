@testable import Core
import Foundation
import Testing

@Test func capsLockBehaviorDefaultsToExistingBehavior() {
    #expect(Config.CapsLockBehavior.default == .capsLock)
    #expect(CapsLockLanguagePolicy.language(capsLockOn: true, behavior: .capsLock) == nil)
    #expect(CapsLockLanguagePolicy.language(capsLockOn: false, behavior: .capsLock) == nil)
}

@Test func capsLockLEDMapsToBothEnglishDirections() {
    #expect(CapsLockLanguagePolicy.language(capsLockOn: true, behavior: .englishWhenOn) == .english)
    #expect(CapsLockLanguagePolicy.language(capsLockOn: false, behavior: .englishWhenOn) == .japanese)
    #expect(CapsLockLanguagePolicy.language(capsLockOn: true, behavior: .englishWhenOff) == .japanese)
    #expect(CapsLockLanguagePolicy.language(capsLockOn: false, behavior: .englishWhenOff) == .english)
}

@Test func capsLockBehaviorIsCodableAndStable() throws {
    for value in [Config.CapsLockBehavior.Value.capsLock, .englishWhenOn, .englishWhenOff] {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Config.CapsLockBehavior.Value.self, from: encoded)
        #expect(decoded == value)
    }
}

@Test func capsLockOffKeepsOriginalKeyEvents() {
    let key = KeyEventCore(modifierFlags: [.shift], characters: "A", charactersIgnoringModifiers: "a", keyCode: 0)
    #expect(CapsLockLanguagePolicy.normalizedEvent(key, capsLockOn: false, behavior: .englishWhenOn) == key)
    #expect(CapsLockLanguagePolicy.normalizedEvent(key, capsLockOn: true, behavior: .capsLock) == key)
}

@Test func capsLockOnEnglishIgnoresAutomaticUppercase() {
    let key = KeyEventCore(modifierFlags: [], characters: "HELLO", charactersIgnoringModifiers: "HELLO", keyCode: 4)
    let result = CapsLockLanguagePolicy.normalizedEvent(key, capsLockOn: true, behavior: .englishWhenOn)
    #expect(result.characters == "hello")
    #expect(result.charactersIgnoringModifiers == "hello")
    #expect(result.modifierFlags == [])
    #expect(result.keyCode == key.keyCode)
}

@Test func capsLockAndShiftProduceUppercaseEnglish() {
    let key = KeyEventCore(modifierFlags: [.shift], characters: "hello", charactersIgnoringModifiers: "HELLO", keyCode: 4)
    let result = CapsLockLanguagePolicy.normalizedEvent(key, capsLockOn: true, behavior: .englishWhenOn)
    #expect(result.characters == "HELLO")
    #expect(result.charactersIgnoringModifiers == "hello")
    #expect(result.modifierFlags == [.shift])
}

@Test func englishWhenOffNormalizesJapaneseRomajiWhileCapsOn() {
    let key = KeyEventCore(modifierFlags: [], characters: "NIHONGO", charactersIgnoringModifiers: "NIHONGO", keyCode: 0)
    let result = CapsLockLanguagePolicy.normalizedEvent(key, capsLockOn: true, behavior: .englishWhenOff)
    #expect(result.characters == "nihongo")
}

@Test func capsLockPreservesNonASCIILayoutCharactersAndSymbols() {
    let key = KeyEventCore(modifierFlags: [], characters: "Àあ@123/ABC", charactersIgnoringModifiers: "Àあ@123/ABC", keyCode: 0)
    let result = CapsLockLanguagePolicy.normalizedEvent(key, capsLockOn: true, behavior: .englishWhenOff)
    #expect(result.characters == "Àあ@123/abc")
}

@Test func manualRomanSelectionSurvivesOrdinaryKeyDown() {
    #expect(!CapsLockLanguagePolicy.shouldSwitch(
        previousCapsLockOn: false, capsLockOn: false, isCapsLockEvent: false
    ))
    #expect(!CapsLockLanguagePolicy.shouldSwitch(
        previousCapsLockOn: true, capsLockOn: true, isCapsLockEvent: false
    ))
    #expect(!CapsLockLanguagePolicy.shouldSwitch(
        previousCapsLockOn: nil, capsLockOn: false, isCapsLockEvent: false
    ))
}

@Test func physicalCapsToggleOrMissedFlagsChangedReenablesAutomaticModeSwitch() {
    #expect(CapsLockLanguagePolicy.shouldSwitch(
        previousCapsLockOn: false, capsLockOn: true, isCapsLockEvent: true
    ))
    #expect(CapsLockLanguagePolicy.shouldSwitch(
        previousCapsLockOn: true, capsLockOn: false, isCapsLockEvent: false
    ))
    #expect(CapsLockLanguagePolicy.shouldSwitch(
        previousCapsLockOn: nil, capsLockOn: true, isCapsLockEvent: true
    ))
}

@Test func manualRomanKeepsCapsLockUppercaseAndDoesNotSwitch() {
    for behavior in [Config.CapsLockBehavior.Value.englishWhenOn, .englishWhenOff] {
        #expect(!CapsLockLanguagePolicy.controlsMode(
            behavior: behavior, inputLanguage: .english, capsManagedRoman: false
        ))
    }
    let uppercase = KeyEventCore(modifierFlags: [], characters: "ABC", charactersIgnoringModifiers: "ABC", keyCode: 0)
    let usedBehavior: Config.CapsLockBehavior.Value = CapsLockLanguagePolicy.controlsMode(
        behavior: .englishWhenOn, inputLanguage: .english, capsManagedRoman: false
    ) ? .englishWhenOn : .capsLock
    #expect(CapsLockLanguagePolicy.normalizedEvent(uppercase, capsLockOn: true, behavior: usedBehavior) == uppercase)
}

@Test func japaneseAndCapsSelectedRomanAllowBidirectionalSwitch() {
    for behavior in [Config.CapsLockBehavior.Value.englishWhenOn, .englishWhenOff] {
        #expect(CapsLockLanguagePolicy.controlsMode(
            behavior: behavior, inputLanguage: .japanese, capsManagedRoman: false
        ))
        #expect(CapsLockLanguagePolicy.controlsMode(
            behavior: behavior, inputLanguage: .english, capsManagedRoman: true
        ))
    }
    #expect(!CapsLockLanguagePolicy.controlsMode(
        behavior: .capsLock, inputLanguage: .japanese, capsManagedRoman: true
    ))
}
