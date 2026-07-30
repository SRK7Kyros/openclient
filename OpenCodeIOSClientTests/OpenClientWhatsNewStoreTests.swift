import XCTest
@testable import OpenClient

@MainActor
final class OpenClientWhatsNewStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OpenClientWhatsNewStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallRecordsVersionWithoutPresenting() {
        let store = makeStore(hasExistingConnection: false)

        XCTAssertNil(store.presentedRelease)

        let nextLaunch = makeStore(hasExistingConnection: true)
        XCTAssertNil(nextLaunch.presentedRelease)
    }

    func testExistingInstallWithoutTrackedVersionPresentsCurrentRelease() {
        let store = makeStore(hasExistingConnection: true)

        XCTAssertEqual(store.presentedRelease?.version, "2.0")
    }

    func testExistingInstallMigrationPresentsCurrentReleaseOnlyOnce() {
        let firstLaunch = makeStore(hasExistingConnection: true)
        XCTAssertEqual(firstLaunch.presentedRelease?.version, "2.0")

        let secondLaunch = makeStore(hasExistingConnection: true)
        XCTAssertNil(secondLaunch.presentedRelease)
    }

    func testTrackedUpgradePresentsCurrentReleaseOnlyOnce() {
        _ = OpenClientWhatsNewStore(
            defaults: defaults,
            currentVersion: "1.0",
            releases: [release],
            hasExistingConnection: false
        )

        let updatedStore = makeStore(hasExistingConnection: false)
        XCTAssertEqual(updatedStore.presentedRelease?.version, "2.0")

        let reopenedStore = makeStore(hasExistingConnection: false)
        XCTAssertNil(reopenedStore.presentedRelease)
    }

    private var release: OpenClientReleaseNotes {
        OpenClientReleaseNotes(
            version: "2.0",
            title: "Release",
            summary: "Summary",
            features: []
        )
    }

    private func makeStore(hasExistingConnection: Bool) -> OpenClientWhatsNewStore {
        OpenClientWhatsNewStore(
            defaults: defaults,
            currentVersion: "2.0",
            releases: [release],
            hasExistingConnection: hasExistingConnection
        )
    }
}
