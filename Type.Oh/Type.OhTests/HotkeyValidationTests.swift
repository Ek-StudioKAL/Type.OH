import Testing
@testable import Type_Oh

struct HotkeyValidationTests {

    @Test func defaultHotkeysAreValidTogether() {
        #expect(validateHotkeys(
            voice: .defaultVoice,
            editor: .defaultEditor,
            scratchpad: .defaultScratchpad
        ) == nil)
    }

    @Test func voiceHotkeyIsRequired() {
        let error = validateHotkeys(
            voice: nil,
            editor: .defaultEditor,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "Dictate needs a hotkey.")
    }

    @Test func editorHotkeyIsRequired() {
        let error = validateHotkeys(
            voice: .defaultVoice,
            editor: nil,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "ReType needs a hotkey.")
    }

    @Test func plainLetterHotkeysNeedAModifier() {
        let error = validateHotkeys(
            voice: HotkeyConfig(keyCode: 0, modifiers: 0),
            editor: .defaultEditor,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "Dictate needs at least one modifier key (or a function key).")
    }

    @Test func functionKeysWorkWithoutModifiers() {
        // F5 (96) alone, F13 (105) alone, F20 (90) alone
        #expect(validateHotkeys(
            voice: HotkeyConfig(keyCode: 96, modifiers: 0),
            editor: HotkeyConfig(keyCode: 105, modifiers: 0),
            scratchpad: HotkeyConfig(keyCode: 90, modifiers: 0)
        ) == nil)
    }

    @Test func duplicateHotkeysAreRejected() {
        let error = validateHotkeys(
            voice: .defaultVoice,
            editor: .defaultVoice,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "Dictate and ReType cannot use the same hotkey.")
    }

    @Test func scratchpadHotkeyCanBeDisabled() {
        #expect(validateHotkeys(
            voice: .defaultVoice,
            editor: .defaultEditor,
            scratchpad: nil
        ) == nil)
    }
}
