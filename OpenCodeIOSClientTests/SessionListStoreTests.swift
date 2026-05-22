import XCTest
@testable import OpenClient

@MainActor
final class SessionListStoreTests: XCTestCase {
    func testGlobalScopePreservesLoadedSessionsWithoutDirectoryFiltering() {
        let store = SessionListStore()
        let global = OpenCodeSession(id: "ses_global", title: "Global", workspaceID: nil, directory: "/", projectID: "global", parentID: nil)
        let project = OpenCodeSession(id: "ses_project", title: "Project", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        XCTAssertEqual(store.sessions([global, project], scopedTo: nil), [global, project])
        XCTAssertEqual(store.sessions([global, project], scopedTo: ""), [global, project])
    }

    func testDirectoryScopeFiltersByExactDirectory() {
        let store = SessionListStore()
        let global = OpenCodeSession(id: "ses_global", title: "Global", workspaceID: nil, directory: "/", projectID: "global", parentID: nil)
        let project = OpenCodeSession(id: "ses_project", title: "Project", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        XCTAssertEqual(store.sessions([global, project], scopedTo: "/tmp/project"), [project])
    }
}
