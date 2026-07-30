import Combine
import XCTest
@testable import OpenClient

@MainActor
final class AppShellFacadeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: OpenClientStorageKey.messageDraftsByChat)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: OpenClientStorageKey.messageDraftsByChat)
        super.tearDown()
    }

    func testPrimarySheetGivesNewProjectChatPrecedenceOverConnection() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let requestID = UUID()

        XCTAssertEqual(shell.primarySheet, .connection)

        viewModel.newProjectChatSheetRequest = NewProjectChatSheetRequest(
            id: requestID,
            projectID: nil,
            workspaceDirectory: nil,
            locksProject: false,
            composerSelection: nil
        )

        guard case let .newProjectChat(request)? = shell.primarySheet else {
            return XCTFail("Expected new-project chat to take precedence")
        }
        XCTAssertEqual(request.id, requestID)

        shell.dismissPrimarySheet()
        XCTAssertEqual(shell.primarySheet, .connection)
    }

    func testAppleIntelligenceCanPresentConnectionContentWithoutDisconnectedBackdrop() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade

        viewModel.isConnected = true
        viewModel.backendMode = .appleIntelligence

        XCTAssertEqual(shell.primarySheet, .connection)
        XCTAssertTrue(shell.showsConnectionSheetContent)
        XCTAssertFalse(shell.hidesShellForConnectionExperience)

        viewModel.backendMode = .none
        viewModel.isConnected = false

        XCTAssertEqual(shell.primarySheet, .connection)
        XCTAssertTrue(shell.hidesShellForConnectionExperience)
    }

    func testProjectLoadingRouteAppliesOnlyToCompactEmptyDirectory() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject()
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.directoryStore.isLoadingSessions = true

        XCTAssertEqual(shell.contentRoute(isCompact: true), .loadingProject)
        XCTAssertEqual(shell.contentRoute(isCompact: false), .projectContent)

        viewModel.directoryStore.sessions = [makeSession()]
        XCTAssertEqual(shell.contentRoute(isCompact: true), .projectContent)
    }

    func testProjectToolbarNewSessionPresentsCurrentContext() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject()
        viewModel.currentProject = project
        viewModel.selectedDirectory = "/tmp/workspace"
        viewModel.selectedProjectContentTab = .sessions

        shell.performProjectContentToolbarAction()

        let request = viewModel.newProjectChatSheetRequest
        XCTAssertEqual(request?.projectID, project.id)
        XCTAssertEqual(request?.workspaceDirectory, "/tmp/workspace")
        XCTAssertEqual(request?.locksProject, true)
        XCTAssertNil(request?.composerSelection)
    }

    func testPluginSetupPresentsPrefilledGlobalChat() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade

        shell.presentPluginSetupChat()

        let request = viewModel.newProjectChatSheetRequest
        XCTAssertEqual(request?.projectID, "global")
        XCTAssertNil(request?.workspaceDirectory)
        XCTAssertEqual(request?.locksProject, true)
        XCTAssertEqual(request?.initialContent?.text, OpenClientPluginSetup.prompt)
        XCTAssertEqual(request?.initialContent?.attachments, [])
        XCTAssertEqual(request?.presentsAboveConnection, true)
    }

    func testDetailRoutePrioritizesGitThenMCPThenServerChat() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject(vcs: "git")
        let session = makeSession()
        let path = "Sources/App.swift"
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.selectedSession = session
        viewModel.selectedProjectContentTab = .git
        viewModel.projectFilesStore.selectedFilePath = path
        viewModel.projectFilesStore.vcsFileStatuses = [
            OpenCodeVCSFileStatus(path: path, added: 1, removed: 0, status: "modified"),
        ]

        XCTAssertEqual(shell.detailRoute(isCompact: false), .gitDiff)

        viewModel.projectFilesStore.vcsFileStatuses = []
        XCTAssertEqual(shell.detailRoute(isCompact: false), .gitFile)

        viewModel.selectedProjectContentTab = .mcp
        XCTAssertEqual(shell.detailRoute(isCompact: false), .mcp)

        viewModel.selectedProjectContentTab = .sessions
        viewModel.backendMode = .server
        viewModel.chatStore.beginSelectingSession(sessionID: session.id, cachedMessages: [])
        XCTAssertEqual(
            shell.detailRoute(isCompact: false),
            .chat(AppShellChatRoute(sessionID: session.id, presentationRequest: 0))
        )
    }

    func testChatRouteWaitsForPreparedSessionAtEverySizeClass() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let session = makeSession()
        viewModel.backendMode = .server
        viewModel.selectedSession = session
        viewModel.chatDetailPresentationRequest = 7

        XCTAssertEqual(shell.detailRoute(isCompact: true), .loadingChat(sessionID: session.id))
        XCTAssertEqual(shell.detailRoute(isCompact: false), .loadingChat(sessionID: session.id))

        viewModel.chatStore.beginSelectingSession(sessionID: session.id, cachedMessages: [])
        XCTAssertEqual(
            shell.detailRoute(isCompact: true),
            .chat(AppShellChatRoute(sessionID: session.id, presentationRequest: 7))
        )
        XCTAssertEqual(
            shell.detailRoute(isCompact: false),
            .chat(AppShellChatRoute(sessionID: session.id, presentationRequest: 7))
        )
    }

    func testAppleIntelligenceSelectedSessionIsExcludedFromRootChatRoute() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        viewModel.backendMode = .appleIntelligence
        viewModel.selectedSession = makeSession()

        XCTAssertEqual(shell.detailRoute(isCompact: false), .selectSession)
    }

    func testGitTabAvailabilityAndInvalidSelectionReconciliation() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject(vcs: nil)
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.selectedProjectContentTab = .git

        XCTAssertEqual(shell.projectContentSnapshot.availableTabs, [.sessions, .mcp])

        shell.reconcileInvalidGitSelection()
        XCTAssertEqual(shell.projectContentSnapshot.selectedTab, .sessions)

        viewModel.currentProject = makeProject(vcs: "git")
        XCTAssertEqual(shell.projectContentSnapshot.availableTabs, [.sessions, .git, .mcp])
    }

    func testSelectingGitPreservesDraftPreparesFilesAndClearsSession() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject(vcs: "git")
        let session = makeSession()
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.selectedSession = session
        viewModel.draftMessage = "Keep this draft"
        viewModel.projectFilesStore.vcsInfo = OpenCodeVCSInfo(branch: "main", defaultBranch: "main")
        viewModel.projectFilesStore.vcsDiffsByMode[.git] = []
        let draftKey = viewModel.messageDraftStorageKey(for: session)

        shell.selectProjectContentTab(.git)

        XCTAssertEqual(viewModel.projectStore.selectedContentTab, .git)
        XCTAssertNil(viewModel.selectedSession)
        XCTAssertEqual(viewModel.projectFilesFacade.selectedWorkspaceDirectory, project.worktree)
        XCTAssertEqual(viewModel.composerStore.draftsByChatKey[draftKey]?.text, "Keep this draft")
    }

    func testSelectingGitWithoutGitProjectDoesNothing() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject(vcs: nil)
        let session = makeSession()
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.selectedSession = session

        shell.selectProjectContentTab(.git)

        XCTAssertEqual(viewModel.projectStore.selectedContentTab, .sessions)
        XCTAssertEqual(viewModel.selectedSession?.id, session.id)
        XCTAssertNil(viewModel.projectFilesFacade.selectedWorkspaceDirectory)
    }

    func testSelectingMCPPreservesDraftAndClearsSession() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let session = makeSession()
        viewModel.currentProject = makeProject()
        viewModel.selectedDirectory = "/tmp/project"
        viewModel.selectedSession = session
        viewModel.draftMessage = "Keep MCP draft"
        viewModel.mcpStore.isReady = true
        let draftKey = viewModel.messageDraftStorageKey(for: session)

        shell.selectProjectContentTab(.mcp)

        XCTAssertEqual(viewModel.projectStore.selectedContentTab, .mcp)
        XCTAssertNil(viewModel.selectedSession)
        XCTAssertEqual(viewModel.composerStore.draftsByChatKey[draftKey]?.text, "Keep MCP draft")
    }

    func testTerminalTabIsAvailableForServerProjectAndClearsSelectedSession() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject(vcs: "git")
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.selectedSession = makeSession()
        viewModel.backendMode = .server
        viewModel.isConnected = true

        XCTAssertTrue(shell.projectContentSnapshot.availableTabs.contains(.terminal))

        shell.selectProjectContentTab(.terminal)

        XCTAssertEqual(viewModel.selectedProjectContentTab, .terminal)
        XCTAssertNil(viewModel.selectedSession)
    }

    func testTerminalDetailRouteUsesSelectedTerminal() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject(vcs: "git")
        let terminal = OpenCodePTY(
            id: "pty_1",
            title: "Terminal 1",
            command: "/bin/zsh",
            args: ["-l"],
            cwd: project.worktree,
            status: "running",
            pid: 42
        )
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.selectedProjectContentTab = .terminal
        viewModel.terminalStore.activate(directory: project.worktree)

        XCTAssertEqual(shell.detailRoute(isCompact: false), .selectTerminal)

        viewModel.terminalStore.append(terminal, directory: project.worktree)

        XCTAssertEqual(shell.detailRoute(isCompact: false), .terminal(id: terminal.id))
    }

    func testObservationRebindsToNewActiveDirectoryStore() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        let project = makeProject()
        viewModel.currentProject = project
        viewModel.selectedDirectory = "/tmp/other"
        let activeStore = viewModel.directoryStoreRegistry.activeStore
        let changed = expectation(description: "App shell observes the new active directory")
        changed.assertForOverFulfill = false
        let observation = shell.objectWillChange.sink { changed.fulfill() }

        activeStore.isLoadingSessions = true

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(shell.contentRoute(isCompact: true), .loadingProject)
        withExtendedLifetime(observation) {}
    }

    func testTranscriptChangesDoNotInvalidateAppShell() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        var changeCount = 0
        let observation = shell.objectWillChange.sink { changeCount += 1 }

        viewModel.objectWillChange.send()
        viewModel.chatStore.messages = [makeMessage()]
        var syncState = viewModel.directoryStore.syncState
        syncState.replaceMessages([makeMessage()], forSessionID: "session")
        viewModel.directoryStore.syncState = syncState

        XCTAssertEqual(changeCount, 0)
        withExtendedLifetime(observation) {}
    }

    func testPreparedSessionStillInvalidatesAppShellRoute() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade
        var changeCount = 0
        let observation = shell.objectWillChange.sink { changeCount += 1 }

        viewModel.chatStore.beginSelectingSession(sessionID: "session", cachedMessages: [])

        XCTAssertGreaterThan(changeCount, 0)
        withExtendedLifetime(observation) {}
    }

    func testBrowserScopeFollowsCurrentProject() {
        let viewModel = AppViewModel()
        let shell = viewModel.appShellFacade

        viewModel.currentProject = makeProject(id: "project-a")
        shell.browser.openAddressBar()
        shell.browser.collapse()

        viewModel.currentProject = makeProject(id: "project-b")
        XCTAssertEqual(shell.browser.activeProjectID, "project-b")
        XCTAssertEqual(shell.browser.presentation, .closed)

        viewModel.currentProject = makeProject(id: "project-a")
        XCTAssertEqual(shell.browser.activeProjectID, "project-a")
        XCTAssertEqual(shell.browser.presentation, .collapsed)
    }

    private func makeProject(id: String = "project", vcs: String? = nil) -> OpenCodeProject {
        OpenCodeProject(
            id: id,
            worktree: "/tmp/\(id)",
            vcs: vcs,
            name: "Project",
            sandboxes: nil,
            icon: nil,
            time: nil
        )
    }

    private func makeSession() -> OpenCodeSession {
        OpenCodeSession(
            id: "session",
            title: "Session",
            workspaceID: nil,
            directory: "/tmp/project",
            projectID: "project",
            parentID: nil
        )
    }

    private func makeMessage() -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: "message", role: "assistant", sessionID: "session", time: nil, agent: nil, model: nil),
            parts: []
        )
    }
}
