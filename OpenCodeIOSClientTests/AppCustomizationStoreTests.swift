import XCTest
@testable import OpenClient

@MainActor
final class AppCustomizationStoreTests: XCTestCase {
    func testSessionCardStylesUseRequestedOrderAndLabels() {
        XCTAssertEqual(SessionCardStyle.allCases, [.compact, .simple, .activity])
        XCTAssertEqual(SessionCardStyle.allCases.map(\.title), ["Compact", "Default", "Activity"])
    }

    func testPreferencesPersistAndDefaultShimmerToEnabled() throws {
        let suiteName = "AppCustomizationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppCustomizationStore(defaults: defaults)
        XCTAssertTrue(store.showsChatActivityShimmer)
        XCTAssertTrue(store.showsActivityLastUserMessage)
        XCTAssertEqual(store.sessionCardStyle, .simple)
        XCTAssertNil(store.autoConnectServerID)

        store.setShowsChatActivityShimmer(false)
        store.setShowsActivityLastUserMessage(false)
        store.setSessionCardStyle(.activity)
        store.setAutoConnectServerID("server-one")

        let restored = AppCustomizationStore(defaults: defaults)
        XCTAssertFalse(restored.showsChatActivityShimmer)
        XCTAssertFalse(restored.showsActivityLastUserMessage)
        XCTAssertEqual(restored.sessionCardStyle, .activity)
        XCTAssertEqual(restored.autoConnectServerID, "server-one")
    }

    func testExistingPreferencesDecodeWithoutRemovedCachePreference() throws {
        let suiteName = "AppCustomizationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "showsChatActivityShimmer": false,
                "autoConnectServerID": "server-one",
            ]),
            forKey: "appCustomizationPreferences"
        )

        let store = AppCustomizationStore(defaults: defaults)

        XCTAssertFalse(store.showsChatActivityShimmer)
        XCTAssertTrue(store.showsActivityLastUserMessage)
        XCTAssertEqual(store.sessionCardStyle, .simple)
        XCTAssertEqual(store.autoConnectServerID, "server-one")
    }

    func testUnknownSessionCardStyleFallsBackToSimpleWithoutDiscardingOtherPreferences() throws {
        let suiteName = "AppCustomizationStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "showsChatActivityShimmer": false,
                "sessionCardStyle": "future-style",
                "autoConnectServerID": "server-one",
            ]),
            forKey: "appCustomizationPreferences"
        )

        let store = AppCustomizationStore(defaults: defaults)

        XCTAssertFalse(store.showsChatActivityShimmer)
        XCTAssertEqual(store.sessionCardStyle, .simple)
        XCTAssertEqual(store.autoConnectServerID, "server-one")
    }

    func testAutoConnectServerSelectionMigratesAndReconciles() {
        let suiteName = "AppCustomizationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = OpenCodeServerConfig(name: "First", baseURL: "https://one.example", username: "opencode")
        let renamed = OpenCodeServerConfig(name: "Renamed", baseURL: "https://two.example", username: "opencode")
        let store = AppCustomizationStore(defaults: defaults)
        store.setAutoConnectServerID(first.recentServerID)

        XCTAssertEqual(store.autoConnectServer(in: [first]), first)

        store.migrateAutoConnectServerID(from: first.recentServerID, to: renamed.recentServerID)
        XCTAssertEqual(store.autoConnectServer(in: [renamed]), renamed)

        store.reconcileAutoConnectServer(in: [])
        XCTAssertNil(store.autoConnectServerID)
    }
}
