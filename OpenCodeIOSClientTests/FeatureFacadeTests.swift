import Combine
import Foundation
import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import OpenClient

@MainActor
final class FeatureFacadeTests: XCTestCase {
    func testSessionRelativeTimeNeverUsesSeconds() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(SessionRelativeTimeText.label(for: now.addingTimeInterval(-20), at: now), "Now")
        XCTAssertEqual(SessionRelativeTimeText.label(for: now.addingTimeInterval(-90), at: now), "1m ago")
        XCTAssertEqual(SessionRelativeTimeText.label(for: now.addingTimeInterval(-3_600), at: now), "1h ago")
    }

    func testSessionListShimmersGeneratedTitleOnlyWhileSessionIsBusy() {
        let session = OpenCodeSession(
            id: "session",
            title: "New session - 2026-08-04T12:00:00.000Z",
            workspaceID: nil,
            directory: nil,
            projectID: "global",
            parentID: nil
        )
        let idleViewModel = AppViewModel()
        idleViewModel.allSessions = [session]
        let busyViewModel = AppViewModel()
        busyViewModel.allSessions = [session]
        busyViewModel.sessionStatuses = [session.id: "busy"]

        XCTAssertFalse(idleViewModel.sessionListFacade.snapshot.unpinnedRows[0].shimmersTitle)
        XCTAssertTrue(busyViewModel.sessionListFacade.snapshot.unpinnedRows[0].shimmersTitle)
    }

    func testSessionListProjectsPreviewIntoSelectedActivityCardStyle() {
        let viewModel = AppViewModel()
        let previousStyle = viewModel.appCustomizationStore.sessionCardStyle
        defer { viewModel.appCustomizationStore.setSessionCardStyle(previousStyle) }
        let session = OpenCodeSession(
            id: "session-activity-card",
            title: "Detailed session",
            workspaceID: nil,
            directory: "/tmp/project",
            projectID: "project",
            parentID: nil
        )
        viewModel.appCustomizationStore.setSessionCardStyle(.activity)
        viewModel.allSessions = [session]
        viewModel.sessionPreviews[session.id] = SessionPreview(text: "Latest assistant reply", date: Date())

        let snapshot = viewModel.sessionListFacade.snapshot
        let row = snapshot.unpinnedRows[0]

        XCTAssertEqual(snapshot.cardStyle, .activity)
        XCTAssertEqual(row.activityRow.latestAssistantText, "Latest assistant reply")
        XCTAssertEqual(row.activityRow.recent.session.id, session.id)
    }

    func testStableUIKitMenuCoordinatorReusesUnchangedMenu() {
        #if canImport(UIKit)
        let coordinator = StableUIKitMenuCoordinator(onSelect: { _ in })
        let elements = [StablePickerMenuElement.action(
            id: "model",
            title: "Model",
            systemImage: "cpu",
            isSelected: false
        )]

        let initialMenu = coordinator.menuIfChanged(for: elements)
        XCTAssertNotNil(initialMenu)
        XCTAssertTrue(initialMenu?.children.first is UIDeferredMenuElement)
        XCTAssertNil(coordinator.menuIfChanged(for: elements))
        XCTAssertNotNil(coordinator.menuIfChanged(for: [
            .action(id: "model", title: "Model", systemImage: "cpu", isSelected: true),
        ]))
        #endif
    }

    func testMCPFacadeSnapshotContainsOnlyMCPState() {
        let store = MCPStore(
            statuses: [
                "zeta": OpenCodeMCPStatus(status: "disabled", error: nil),
                "alpha": OpenCodeMCPStatus(status: "connected", error: nil),
            ],
            isReady: true,
            isLoading: true,
            togglingServerNames: ["alpha"]
        )
        let facade = MCPFacade(
            store: store,
            clientProvider: { OpenCodeAPIClient(config: OpenCodeServerConfig()) },
            directoryProvider: { "/tmp/project" }
        )

        let snapshot = facade.snapshot

        XCTAssertEqual(snapshot.servers.map(\.name), ["alpha", "zeta"])
        XCTAssertEqual(snapshot.connectedServerCount, 1)
        XCTAssertTrue(snapshot.isLoading)
        XCTAssertEqual(snapshot.togglingServerNames, ["alpha"])
    }

    func testProjectFilesFacadeBuildsPreparedSnapshot() {
        let path = "Sources/App.swift"
        let directory = makeFileNode(
            name: "Sources",
            path: "Sources",
            absolute: "/tmp/project/Sources",
            type: "directory"
        )
        let file = makeFileNode(
            name: "App.swift",
            path: path,
            absolute: "/tmp/project/\(path)"
        )
        let store = ProjectFilesStore(
            vcsInfo: OpenCodeVCSInfo(branch: "feature", defaultBranch: "main"),
            vcsFileStatuses: [
                OpenCodeVCSFileStatus(path: path, added: 3, removed: 1, status: "modified"),
            ],
            vcsDiffsByMode: [
                .git: [OpenCodeVCSFileDiff(file: path, patch: "@@", additions: 3, deletions: 1, status: "modified")],
            ],
            selectedVCSFile: path,
            fileTreeRootNodes: [directory],
            fileTreeChildrenByParentPath: [directory.absolute: [file]],
            expandedFileTreeDirectories: [directory.absolute],
            selectedFilePath: path,
            fileContentsByPath: [
                path: OpenCodeFileContent(type: "text", content: "print(\"hi\")", diff: nil, encoding: "utf-8", mimeType: "text/x-swift"),
            ]
        )
        let facade = makeProjectFilesFacade(store: store)

        let snapshot = facade.snapshot

        XCTAssertEqual(snapshot.summary.fileCount, 1)
        XCTAssertEqual(snapshot.summary.additions, 3)
        XCTAssertEqual(snapshot.fileStatuses.map(\.path), [path])
        XCTAssertEqual(snapshot.selectedVCSFile, path)
        XCTAssertEqual(snapshot.filesMode, .changes)
        XCTAssertEqual(snapshot.visibleRows.map(\.node.name), ["Sources", "App.swift"])
        XCTAssertEqual(snapshot.selectedFileDiff?.file, path)
        XCTAssertEqual(snapshot.selectedFileContent?.content, "print(\"hi\")")
    }

    func testProjectFilesFacadeResetClearsWorkspaceAndStoreState() {
        let store = ProjectFilesStore(
            vcsInfo: OpenCodeVCSInfo(branch: "main", defaultBranch: "main"),
            vcsFileStatuses: [OpenCodeVCSFileStatus(path: "README.md", added: 1, removed: 0, status: "modified")]
        )
        let facade = makeProjectFilesFacade(store: store)
        facade.selectedWorkspaceDirectory = "/tmp/project"

        facade.reset()

        XCTAssertNil(facade.selectedWorkspaceDirectory)
        XCTAssertNil(store.vcsInfo)
        XCTAssertTrue(store.vcsFileStatuses.isEmpty)
    }

    func testProjectFilesManualAndWatcherRefreshReplaceCachedDiffWhenRepositoryBecomesClean() async throws {
        let path = "Sources/App.swift"
        let store = ProjectFilesStore(
            vcsInfo: OpenCodeVCSInfo(branch: "main", defaultBranch: "main"),
            vcsFileStatuses: [
                OpenCodeVCSFileStatus(path: path, added: 3, removed: 1, status: "modified"),
            ],
            vcsDiffsByMode: [
                .git: [OpenCodeVCSFileDiff(file: path, patch: "@@", additions: 3, deletions: 1, status: "modified")],
            ],
            selectedVCSFile: path,
            selectedFilePath: path
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProjectFilesMockURLProtocol.self]
        let client = OpenCodeAPIClient(
            config: OpenCodeServerConfig(baseURL: "http://127.0.0.1:4096", username: "opencode", password: "pw"),
            session: URLSession(configuration: configuration)
        )
        let facade = makeProjectFilesFacade(store: store, client: client)
        ProjectFilesMockURLProtocol.requestHandler = { request in
            let body: String
            switch request.url?.path {
            case "/vcs":
                body = #"{"branch":"main","default_branch":"main"}"#
            case "/file/status", "/vcs/diff":
                body = "[]"
            default:
                throw URLError(.badURL)
            }
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }
        defer { ProjectFilesMockURLProtocol.requestHandler = nil }

        await facade.refresh()

        XCTAssertTrue(store.vcsFileStatuses.isEmpty)
        XCTAssertEqual(store.vcsDiffsByMode[.git], [])

        store.vcsFileStatuses = [
            OpenCodeVCSFileStatus(path: path, added: 3, removed: 1, status: "modified"),
        ]
        store.vcsDiffsByMode[.git] = [
            OpenCodeVCSFileDiff(file: path, patch: "@@", additions: 3, deletions: 1, status: "modified"),
        ]
        let cacheCleared = expectation(description: "Fresh empty diff replaces the cached diff")
        let observation = store.$vcsDiffsByMode.dropFirst().sink { diffs in
            if diffs[.git] == [] {
                cacheCleared.fulfill()
            }
        }

        facade.handleFileWatcherUpdate(".git/index")
        await fulfillment(of: [cacheCleared], timeout: 2)

        XCTAssertTrue(store.vcsFileStatuses.isEmpty)
        XCTAssertEqual(store.vcsDiffsByMode[.git], [])
        withExtendedLifetime(observation) {}
    }

    func testProjectFacadeBuildsListAndSettingsSnapshots() {
        let viewModel = AppViewModel()
        let project = OpenCodeProject(
            id: "project",
            worktree: "/tmp/project",
            vcs: "git",
            name: "Project",
            sandboxes: nil,
            icon: nil,
            time: nil
        )
        let action = OpenCodeAction(commandName: "review", iconName: "checkmark")
        let review = OpenCodeCommand(
            name: "review",
            description: "Review changes",
            agent: nil,
            model: nil,
            source: "project",
            template: "review",
            subtask: false,
            hints: []
        )
        let test = OpenCodeCommand(
            name: "test",
            description: "Run tests",
            agent: nil,
            model: nil,
            source: "project",
            template: "test",
            subtask: false,
            hints: []
        )
        viewModel.projects = [project]
        viewModel.currentProject = project
        viewModel.selectedDirectory = project.worktree
        viewModel.directoryCommands = [review, test]
        viewModel.projectActionsByScope[viewModel.currentProjectPreferenceScopeKey] = [action]

        let list = viewModel.projectFacade.listSnapshot
        let settings = viewModel.projectFacade.settingsSnapshot

        XCTAssertEqual(list.projects, [project])
        XCTAssertEqual(list.currentProjectID, project.id)
        XCTAssertEqual(list.selectedDirectory, project.worktree)
        XCTAssertEqual(settings.actions.map(\.action), [action])
        XCTAssertEqual(settings.actions.first?.command, review)
        XCTAssertEqual(settings.addableCommands.map(\.name), ["test"])
        XCTAssertTrue(settings.hasGitProject)
    }

    func testSessionSelectionCommitsRouteBeforePreparingCachedTranscript() {
        let viewModel = AppViewModel()
        let first = OpenCodeSession(
            id: "session-first",
            title: "First",
            workspaceID: nil,
            directory: "/tmp/project",
            projectID: "project",
            parentID: nil
        )
        let second = OpenCodeSession(
            id: "session-second",
            title: "Second",
            workspaceID: nil,
            directory: "/tmp/project",
            projectID: "project",
            parentID: nil
        )
        viewModel.selectedDirectory = "/tmp/project"
        viewModel.allSessions = [first, second]
        viewModel.selectedSession = first
        let previousMessage = OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: "message-first", role: "assistant", sessionID: first.id, time: nil, agent: nil, model: nil),
            parts: []
        )
        let selectedMessage = OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: "message-second", role: "assistant", sessionID: second.id, time: nil, agent: nil, model: nil),
            parts: []
        )
        viewModel.chatStore.messages = [previousMessage]
        viewModel.chatStore.cacheMessages([selectedMessage], forSessionID: second.id)

        let ticket = viewModel.sessionListFacade.beginSelection(second)

        XCTAssertEqual(viewModel.selectedSession?.id, second.id)
        XCTAssertEqual(viewModel.directoryStore.selectedSession?.id, second.id)
        XCTAssertNil(viewModel.chatStore.preparedSessionID)
        XCTAssertEqual(viewModel.chatStore.messages.map(\.id), [previousMessage.id])
        XCTAssertTrue(viewModel.chatStore.isLoadingSelectedSession)
        XCTAssertEqual(viewModel.appShellFacade.detailRoute(isCompact: true), .loadingChat(sessionID: second.id))

        XCTAssertTrue(viewModel.sessionListFacade.prepareSelectionIfCurrent(ticket))

        XCTAssertEqual(viewModel.chatStore.preparedSessionID, second.id)
        XCTAssertEqual(viewModel.chatStore.messages.map(\.id), [selectedMessage.id])
        XCTAssertEqual(
            viewModel.appShellFacade.detailRoute(isCompact: true),
            .chat(AppShellChatRoute(sessionID: second.id, presentationRequest: 0))
        )
    }

    func testStaleSessionSelectionTicketDoesNotPreparePreviousTarget() {
        let viewModel = AppViewModel()
        let first = OpenCodeSession(id: "session-first", title: "First", workspaceID: nil, directory: "/tmp/project", projectID: "project", parentID: nil)
        let second = OpenCodeSession(id: "session-second", title: "Second", workspaceID: nil, directory: "/tmp/project", projectID: "project", parentID: nil)
        viewModel.selectedDirectory = "/tmp/project"
        viewModel.allSessions = [first, second]

        let firstTicket = viewModel.sessionListFacade.beginSelection(first)
        let secondTicket = viewModel.sessionListFacade.beginSelection(second)
        XCTAssertFalse(viewModel.sessionListFacade.prepareSelectionIfCurrent(firstTicket))

        XCTAssertNil(viewModel.chatStore.preparedSessionID)

        XCTAssertTrue(viewModel.sessionListFacade.prepareSelectionIfCurrent(secondTicket))

        XCTAssertEqual(viewModel.chatStore.preparedSessionID, second.id)
    }

    func testTranscriptChangesDoNotInvalidateProjectListFacades() {
        let viewModel = AppViewModel()
        let projects = viewModel.projectFacade
        let sessions = viewModel.sessionListFacade
        let connection = viewModel.connectionFacade
        let configurations = viewModel.configurationsFacade
        let games = viewModel.funAndGamesFacade
        var projectChanges = 0
        var sessionChanges = 0
        var connectionChanges = 0
        var configurationChanges = 0
        var gameChanges = 0
        let observations = [
            projects.objectWillChange.sink { projectChanges += 1 },
            sessions.objectWillChange.sink { sessionChanges += 1 },
            connection.objectWillChange.sink { connectionChanges += 1 },
            configurations.objectWillChange.sink { configurationChanges += 1 },
            games.objectWillChange.sink { gameChanges += 1 },
        ]

        viewModel.objectWillChange.send()
        viewModel.chatStore.messages = [OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: "message", role: "assistant", sessionID: "session", time: nil, agent: nil, model: nil),
            parts: []
        )]
        var syncState = viewModel.directoryStore.syncState
        syncState.replaceMessages(viewModel.chatStore.messages, forSessionID: "session")
        viewModel.directoryStore.syncState = syncState

        XCTAssertEqual(projectChanges, 0)
        XCTAssertEqual(sessionChanges, 0)
        XCTAssertEqual(connectionChanges, 0)
        XCTAssertEqual(configurationChanges, 0)
        XCTAssertEqual(gameChanges, 0)
        withExtendedLifetime(observations) {}
    }

    func testStreamingSessionStateDoesNotInvalidateNewProjectChatFacade() {
        let viewModel = AppViewModel()
        let facade = viewModel.newProjectChatFacade
        var changes = 0
        let observation = facade.objectWillChange.sink { changes += 1 }

        viewModel.chatStore.messages = [OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: "message", role: "assistant", sessionID: "session", time: nil, agent: nil, model: nil),
            parts: []
        )]
        viewModel.sessionListStore.previews = [:]
        viewModel.sessionListStore.workspaceSessionsByDirectory["/tmp/project"] = OpenCodeWorkspaceSessionState()
        viewModel.modelConfigurationStore.selectedAgentNamesBySessionID["session"] = "build"
        viewModel.modelConfigurationStore.selectedModelsBySessionID["session"] = OpenCodeModelReference(
            providerID: "provider",
            modelID: "model"
        )
        viewModel.modelConfigurationStore.selectedVariantsBySessionID["session"] = "high"
        viewModel.directoryStore.sessionStatuses = ["session": "busy"]
        var syncState = viewModel.directoryStore.syncState
        syncState.replaceMessages(viewModel.chatStore.messages, forSessionID: "session")
        viewModel.directoryStore.syncState = syncState

        XCTAssertEqual(changes, 0)

        viewModel.modelConfigurationStore.availableAgents = [
            OpenCodeAgent(name: "build", description: nil, mode: "primary", hidden: false, model: nil, variant: nil)
        ]

        XCTAssertEqual(changes, 1)
        withExtendedLifetime(observation) {}
    }

    func testSustainedTranscriptDeltaFlushDoesNotInvalidateNewProjectChatFacade() {
        let viewModel = AppViewModel()
        let directory = "/tmp/project"
        let session = OpenCodeSession(
            id: "session",
            title: "Streaming",
            workspaceID: nil,
            directory: directory,
            projectID: "project",
            parentID: nil
        )
        let message = OpenCodeMessage(id: "message", role: "assistant", sessionID: session.id, time: nil, agent: nil, model: nil)
        let part = OpenCodePart(
            id: "part",
            messageID: message.id,
            sessionID: session.id,
            type: "text",
            mime: nil,
            filename: nil,
            url: nil,
            reason: nil,
            tool: nil,
            callID: nil,
            state: nil,
            text: ""
        )
        viewModel.isConnected = true
        viewModel.selectedDirectory = session.directory
        viewModel.selectedSession = session
        viewModel.activeChatSessionID = session.id
        viewModel.handleManagedEvent(OpenCodeManagedEvent(
            directory: directory,
            envelope: OpenCodeEventEnvelope(type: "message.updated", properties: OpenCodeEventProperties(info: OpenCodeEventInfo(message: message))),
            typed: .messageUpdated(message)
        ))
        viewModel.handleManagedEvent(OpenCodeManagedEvent(
            directory: directory,
            envelope: OpenCodeEventEnvelope(type: "message.part.updated", properties: OpenCodeEventProperties(part: part)),
            typed: .messagePartUpdated(part)
        ))

        let facade = viewModel.newProjectChatFacade
        var changes = 0
        let observation = facade.objectWillChange.sink { changes += 1 }
        var sourceChanges: [String: Int] = [:]
        let sourceObservations = [
            viewModel.projectStore.$projects.dropFirst().sink { _ in sourceChanges["projects", default: 0] += 1 },
            viewModel.projectStore.$currentProject.dropFirst().sink { _ in sourceChanges["currentProject", default: 0] += 1 },
            viewModel.projectPreferencesStore.$projectWorkspacesEnabledByScope.dropFirst().sink { _ in sourceChanges["workspaces", default: 0] += 1 },
            viewModel.modelConfigurationStore.$availableAgents.dropFirst().sink { _ in sourceChanges["agents", default: 0] += 1 },
            viewModel.modelConfigurationStore.$allProviders.dropFirst().sink { _ in sourceChanges["allProviders", default: 0] += 1 },
            viewModel.modelConfigurationStore.$availableProviders.dropFirst().sink { _ in sourceChanges["providers", default: 0] += 1 },
            viewModel.modelConfigurationStore.$defaultModelsByProviderID.dropFirst().sink { _ in sourceChanges["defaults", default: 0] += 1 },
            viewModel.modelConfigurationStore.$newSessionDefaults.dropFirst().sink { _ in sourceChanges["newSessionDefaults", default: 0] += 1 },
        ]

        for _ in 0..<100 {
            let event = OpenCodeManagedEvent(
                directory: directory,
                envelope: OpenCodeEventEnvelope(
                    type: "message.part.delta",
                    properties: OpenCodeEventProperties(
                        sessionID: session.id,
                        messageID: message.id,
                        partID: part.id,
                        field: "text",
                        delta: "x"
                    )
                ),
                typed: .messagePartDelta(
                    sessionID: session.id,
                    messageID: message.id,
                    partID: part.id ?? "part",
                    field: "text",
                    delta: "x"
                )
            )
            viewModel.handleManagedEvent(event)
        }
        viewModel.flushBufferedTranscript(reason: "new chat picker stability test")

        XCTAssertEqual(viewModel.messages.first?.parts.first?.text?.count, 100)
        XCTAssertEqual(changes, 0, "Sources: \(sourceChanges)")
        withExtendedLifetime(observation) {}
        withExtendedLifetime(sourceObservations) {}
    }

    func testExtractedFacadesRemainSafeAfterAppViewModelDeinitializes() async {
        var viewModel: AppViewModel? = AppViewModel()
        let projectFilesFacade = viewModel!.projectFilesFacade
        let mcpFacade = viewModel!.mcpFacade
        let widgetSnapshotPublisher = viewModel!.widgetSnapshotPublisher
        weak let weakViewModel = viewModel

        viewModel = nil

        XCTAssertNil(weakViewModel)
        XCTAssertFalse(projectFilesFacade.hasGitProject)
        XCTAssertNil(projectFilesFacade.snapshot.effectiveDirectory)
        await projectFilesFacade.reloadGitViewData(force: true)
        await mcpFacade.reload()
        await widgetSnapshotPublisher.publishNow()
    }

    private func makeProjectFilesFacade(
        store: ProjectFilesStore,
        client: OpenCodeAPIClient = OpenCodeAPIClient(config: OpenCodeServerConfig())
    ) -> ProjectFilesFacade {
        ProjectFilesFacade(
            store: store,
            clientProvider: { client },
            hasGitProjectProvider: { true },
            effectiveSelectedDirectoryProvider: { "/tmp/project" },
            currentProjectProvider: {
                OpenCodeProject(id: "project", worktree: "/tmp/project", vcs: "git", name: "Project", sandboxes: nil, icon: nil, time: nil)
            },
            workspaceDirectoriesProvider: { ["/tmp/project"] },
            workspaceDisplayNameProvider: { _ in "Project" },
            workspaceKeyProvider: { $0 },
            isFilesPresentedProvider: { true },
            preserveNavigationState: {},
            showFilesRoute: {}
        )
    }

    private func makeFileNode(
        name: String,
        path: String,
        absolute: String,
        type: String = "file"
    ) -> OpenCodeFileNode {
        OpenCodeFileNode(name: name, path: path, absolute: absolute, type: type, ignored: false)
    }
}

private final class ProjectFilesMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Missing request handler")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
