import Testing
@testable import Type_Oh

@MainActor
struct ModelManagerTests {

    @Test func catalogueContainsFiveModels() {
        #expect(ModelManager.shared.catalogue.count == 5)
    }

    @Test func catalogueContainsBaseModel() {
        let ids = ModelManager.shared.catalogue.map(\.id)
        #expect(ids.contains("openai_whisper-base"))
    }

    @Test func allCatalogueEntriesHaveNonEmptyFields() {
        for m in ModelManager.shared.catalogue {
            #expect(!m.id.isEmpty,              "\(m.displayName) has empty id")
            #expect(!m.displayName.isEmpty,     "model '\(m.id)' has empty displayName")
            #expect(!m.sizeDescription.isEmpty, "\(m.displayName) has empty sizeDescription")
        }
    }

    @Test func isNotDownloadedForFreshID() {
        #expect(!ModelManager.shared.isDownloaded("nonexistent_model_id"))
    }

    @Test func modelFolderURLNilForUnknownModel() {
        #expect(ModelManager.shared.modelFolderURL(for: "nonexistent_model_id") == nil)
    }

    @Test func processResidentMBIsPositive() {
        #expect(ModelManager.processResidentMB > 0)
    }
}
