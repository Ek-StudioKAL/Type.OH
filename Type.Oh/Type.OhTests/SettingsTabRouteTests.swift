import Foundation
import Testing
@testable import Type_Oh

struct SettingsTabRouteTests {

    private func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "typeoh-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func pendingTabRoundTripsAndConsumesOnce() throws {
        let defaults = try isolatedDefaults()

        SettingsTabRoute.setPendingTab(.presets, defaults: defaults)

        #expect(SettingsTabRoute.consumePendingTab(defaults: defaults) == .presets)
        #expect(SettingsTabRoute.consumePendingTab(defaults: defaults) == nil)
    }

    @Test func invalidPendingTabIsDiscarded() throws {
        let defaults = try isolatedDefaults()
        defaults.set("not-a-tab", forKey: "typeoh.pendingSettingsTab")

        #expect(SettingsTabRoute.consumePendingTab(defaults: defaults) == nil)
        #expect(defaults.string(forKey: "typeoh.pendingSettingsTab") == nil)
    }

    @Test func openStoresTheRequestedTabBeforePosting() throws {
        let defaults = try isolatedDefaults()

        SettingsTabRoute.open(.translation, defaults: defaults)

        #expect(SettingsTabRoute.consumePendingTab(defaults: defaults) == .translation)
    }

    @Test func settingsTabRawValuesRemainStable() {
        #expect(SettingsTab.general.rawValue == "general")
        #expect(SettingsTab.providers.rawValue == "providers")
        #expect(SettingsTab.presets.rawValue == "presets")
        #expect(SettingsTab.translation.rawValue == "translation")
        #expect(SettingsTab.models.rawValue == "models")
    }
}
