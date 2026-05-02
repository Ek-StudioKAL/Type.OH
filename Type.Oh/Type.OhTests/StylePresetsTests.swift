import Testing
@testable import Type_Oh

struct StylePresetsTests {

    @Test func fivePresetsExist() {
        #expect(StylePresets.all.count == 5)
    }

    @Test func allPresetsHaveNonEmptyFields() {
        for preset in StylePresets.all {
            #expect(!preset.id.isEmpty,            "\(preset.label) has empty id")
            #expect(!preset.label.isEmpty,          "preset with id '\(preset.id)' has empty label")
            #expect(!preset.emoji.isEmpty,          "\(preset.label) has empty emoji")
            #expect(!preset.promptFragment.isEmpty, "\(preset.label) has empty promptFragment")
        }
    }

    @Test func idsAreUnique() {
        let ids = StylePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count, "Preset ids are not unique: \(ids)")
    }

    @Test func knownPresetsPresent() {
        let ids = Set(StylePresets.all.map(\.id))
        for expected in ["formal", "concise", "friendly", "corporate", "pirate"] {
            #expect(ids.contains(expected), "Missing preset: \(expected)")
        }
    }
}
