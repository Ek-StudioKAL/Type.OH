import Foundation
import Testing
@testable import Type_Oh

@MainActor
struct ScratchpadStoreTests {

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typeoh-scratchpad-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func freshStoreLoadsEmptyText() throws {
        let store = ScratchpadStore(directoryURL: try temporaryDirectory())

        #expect(store.load() == "")
    }

    @Test func saveNowPersistsTextForNextStore() throws {
        let directory = try temporaryDirectory()
        let text = "line one\nline two\nline three"

        ScratchpadStore(directoryURL: directory).saveNow(text)

        #expect(ScratchpadStore(directoryURL: directory).load() == text)
    }

    @Test func scheduleSavePersistsLatestTextOnly() async throws {
        let directory = try temporaryDirectory()
        let store = ScratchpadStore(directoryURL: directory)

        store.scheduleSave("old text")
        store.scheduleSave("new text")

        try await Task.sleep(for: .milliseconds(650))

        #expect(ScratchpadStore(directoryURL: directory).load() == "new text")
    }

    @Test func saveNowCancelsPendingDebouncedSave() async throws {
        let directory = try temporaryDirectory()
        let store = ScratchpadStore(directoryURL: directory)

        store.scheduleSave("pending text")
        store.saveNow("immediate text")

        try await Task.sleep(for: .milliseconds(650))

        #expect(ScratchpadStore(directoryURL: directory).load() == "immediate text")
    }
}
