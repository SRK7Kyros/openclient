import XCTest
@testable import OpenClient

@MainActor
final class SessionListStoreTests: XCTestCase {
    func testDefaultGeneratedRootTitleIsDetectedAndDisplayedLikeUpstream() {
        let session = OpenCodeSession(id: "ses_default", title: "New session - 2026-05-26T12:34:56.789Z", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        XCTAssertTrue(session.isDefaultGeneratedTitle)
        XCTAssertEqual(session.defaultGeneratedTitleDisplayName, "New session")
        XCTAssertEqual(session.displayTitle(), "New session")
    }

    func testDefaultGeneratedChildTitleIsDetectedAndDisplayedLikeUpstream() {
        let session = OpenCodeSession(id: "ses_child", title: "Child session - 2026-05-26T12:34:56.789Z", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: "ses_parent")

        XCTAssertTrue(session.isDefaultGeneratedTitle)
        XCTAssertEqual(session.defaultGeneratedTitleDisplayName, "Child session")
        XCTAssertEqual(session.displayTitle(), "Child session")
    }

    func testInvalidDefaultGeneratedTitleShapeIsNotDetected() {
        let session = OpenCodeSession(id: "ses_invalid", title: "New session - 2026-05-26", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        XCTAssertFalse(session.isDefaultGeneratedTitle)
        XCTAssertNil(session.defaultGeneratedTitleDisplayName)
        XCTAssertEqual(session.displayTitle(), "New session - 2026-05-26")
    }

    func testCustomSessionTitleIsDisplayedUnchanged() {
        let session = OpenCodeSession(id: "ses_custom", title: "Fix streaming title shimmer", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        XCTAssertFalse(session.isDefaultGeneratedTitle)
        XCTAssertEqual(session.displayTitle(), "Fix streaming title shimmer")
    }

    func testReconcileWorkspaceSessionsUpdatesStaleLiveTitleCache() {
        let store = SessionListStore()
        let stale = OpenCodeSession(id: "ses_test", title: "New session - 2026-05-26T12:34:56.789Z", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)
        let renamed = OpenCodeSession(id: "ses_test", title: "Generated title", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)
        store.finishWorkspaceSessionsLoading([stale], estimatedTotal: 1, limit: 55, directory: "/tmp/project")

        XCTAssertTrue(store.reconcileWorkspaceSessions(with: [renamed]))
        XCTAssertEqual(store.workspaceSessionsByDirectory["/tmp/project"]?.sessions.first?.title, "Generated title")
    }

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

    func testApplyDirectoryReloadSessionsStoresRecentsAndReturnsScopedSessions() {
        let store = SessionListStore()
        let global = OpenCodeSession(id: "ses_global", title: "Global", workspaceID: nil, directory: "/", projectID: "global", parentID: nil)
        let project = OpenCodeSession(id: "ses_project", title: "Project", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        let visible = store.applyDirectoryReloadSessions([global, project], scopedTo: "/tmp/project")

        XCTAssertEqual(visible, [project])
        XCTAssertEqual(store.recentSessionsByDirectory["/tmp/project"], [global, project])
    }

    func testDirectoryReloadDeduplicatesSessionIDs() {
        let store = SessionListStore()
        let stale = OpenCodeSession(id: "ses_duplicate", title: "Stale", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)
        let updated = OpenCodeSession(id: "ses_duplicate", title: "Updated", workspaceID: nil, directory: "/tmp/project", projectID: "proj", parentID: nil)

        let sessions = store.applyDirectoryReloadSessions([stale, updated], scopedTo: "/tmp/project")

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.title, "Updated")
    }

    func testRecentSessionPrefersExplicitDirectoryProjectOverRepositoryProjectID() {
        let store = SessionListStore()
        let repository = OpenCodeProject(id: "repo", worktree: "/tmp/repo", vcs: "git", name: "opencode", sandboxes: nil, icon: nil, time: nil)
        let general = OpenCodeProject(id: "local:/tmp/repo/general", worktree: "/tmp/repo/general", vcs: nil, name: "General", sandboxes: nil, icon: nil, time: nil)
        let session = OpenCodeSession(id: "session", title: "General work", workspaceID: nil, directory: general.worktree, projectID: repository.id, parentID: nil)
        store.setRecentSessions([session], for: general.worktree)

        let recent = store.recentProjectSessions(projects: [repository, general], previews: [:], statuses: [:])

        XCTAssertEqual(recent.first?.projectTitle, "General")
    }

    func testBareSessionScopeAttributesRepositorySessionToGlobalProject() {
        let store = SessionListStore()
        let global = OpenCodeProject(id: "global", worktree: "/", vcs: nil, name: nil, sandboxes: nil, icon: nil, time: nil)
        let repository = OpenCodeProject(id: "repo", worktree: "/tmp/repo", vcs: "git", name: "opencode", sandboxes: nil, icon: nil, time: nil)
        let session = OpenCodeSession(id: "session", title: "Freeing up disk space", workspaceID: nil, directory: "/tmp/repo/subdirectory", projectID: repository.id, parentID: nil)
        store.setRecentSessions([session], for: nil)

        let recent = store.recentProjectSessions(projects: [global, repository], previews: [:], statuses: [:])

        XCTAssertEqual(recent.first?.projectTitle, "Global")
        XCTAssertEqual(recent.first?.session.projectID, "global")
    }

    func testExplicitScopeWinsWhenSessionAlsoAppearsInBareScope() {
        let store = SessionListStore()
        let global = OpenCodeProject(id: "global", worktree: "/", vcs: nil, name: nil, sandboxes: nil, icon: nil, time: nil)
        let repository = OpenCodeProject(id: "repo", worktree: "/tmp/repo", vcs: "git", name: "opencode", sandboxes: nil, icon: nil, time: nil)
        let session = OpenCodeSession(id: "session", title: "Repository work", workspaceID: nil, directory: repository.worktree, projectID: repository.id, parentID: nil)
        store.setRecentSessions([session], for: nil)
        store.setRecentSessions([session], for: repository.worktree)

        let recent = store.recentProjectSessions(projects: [global, repository], previews: [:], statuses: [:])

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.projectTitle, "opencode")
        XCTAssertEqual(recent.first?.session.projectID, repository.id)
    }

    func testRemovingRecentSessionClearsEverySourceScope() {
        let store = SessionListStore()
        let session = OpenCodeSession(id: "session", title: "Delete me", workspaceID: nil, directory: "/tmp/project", projectID: "project", parentID: nil)
        store.setRecentSessions([session], for: nil)
        store.setRecentSessions([session], for: session.directory)

        XCTAssertTrue(store.removeRecentSession(sessionID: session.id))
        XCTAssertTrue(store.recentSessionsByDirectory.values.allSatisfy(\.isEmpty))
        XCTAssertFalse(store.removeRecentSession(sessionID: session.id))
    }
}
