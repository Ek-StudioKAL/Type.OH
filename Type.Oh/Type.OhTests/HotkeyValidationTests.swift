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

        #expect(error == "Voice recording needs a hotkey.")
    }

    @Test func editorHotkeyIsRequired() {
        let error = validateHotkeys(
            voice: .defaultVoice,
            editor: nil,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "AI Editor needs a hotkey.")
    }

    @Test func plainLetterHotkeysNeedAModifier() {
        let error = validateHotkeys(
            voice: HotkeyConfig(keyCode: 0, modifiers: 0),
            editor: .defaultEditor,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "Voice recording needs at least one modifier key (or an F13–F19 key).")
    }

    @Test func duplicateHotkeysAreRejected() {
        let error = validateHotkeys(
            voice: .defaultVoice,
            editor: .defaultVoice,
            scratchpad: .defaultScratchpad
        )

        #expect(error == "Voice recording and AI Editor cannot use the same hotkey.")
    }

    @Test func scratchpadHotkeyCanBeDisabled() {
        #expect(validateHotkeys(
            voice: .defaultVoice,
            editor: .defaultEditor,
            scratchpad: nil
        ) == nil)
    }
}
