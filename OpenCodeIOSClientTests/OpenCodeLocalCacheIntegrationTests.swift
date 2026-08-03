import XCTest
@testable import OpenClient

@MainActor
final class OpenCodeLocalCacheIntegrationTests: XCTestCase {
    func testPersistentCacheHydratesWithoutAUserPreference() async throws {
        let viewModel = AppViewModel()
        viewModel.config = serverConfig
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        viewModel.localCacheRepository = repository
        try await repository.saveProjects([project], serverID: serverConfig.recentServerID)

        let snapshot = await viewModel.loadCachedProjectsIfEnabled()

        XCTAssertEqual(snapshot?.projects, [project])
    }

    func testDirectoryAndChatCacheHydrateThroughExistingStores() async throws {
        let viewModel = AppViewModel()
        viewModel.config = serverConfig
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        viewModel.localCacheRepository = repository

        try await repository.saveDirectorySessions(
            [session],
            serverID: serverConfig.recentServerID,
            directory: session.directory
        )
        try await repository.saveChatMessages(
            [message],
            serverID: serverConfig.recentServerID,
            sessionID: session.id
        )
        try await repository.saveTodos(
            [todo],
            serverID: serverConfig.recentServerID,
            sessionID: session.id
        )

        viewModel.selectedDirectory = session.directory
        let directorySnapshot = await viewModel.hydrateDirectoryFromLocalCache(session.directory)
        viewModel.selectedSession = session
        let chatSnapshot = await viewModel.hydrateChatFromLocalCache(session)

        XCTAssertEqual(directorySnapshot?.sessions, [session])
        XCTAssertEqual(viewModel.directoryStore.sessions, [session])
        XCTAssertEqual(chatSnapshot?.messages, [message])
        XCTAssertEqual(viewModel.directoryStore.syncState.messageEnvelopes(forSessionID: session.id), [message])
        XCTAssertEqual(viewModel.directoryStore.syncState.todosBySessionID[session.id], [todo])
    }

    func testProjectNavigationHydratesCachedSessionsBeforeTheProjectRouteIsExposed() async throws {
        let viewModel = AppViewModel()
        viewModel.config = serverConfig
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        viewModel.localCacheRepository = repository
        try await repository.saveDirectorySessions(
            [session],
            serverID: serverConfig.recentServerID,
            directory: project.worktree
        )

        _ = await viewModel.prepareProjectNavigation(project)

        XCTAssertEqual(viewModel.selectedDirectory, project.worktree)
        XCTAssertEqual(viewModel.directoryStore.sessions, [session])
        XCTAssertTrue(viewModel.isLoadingSessions)
    }

    func testSelectionPreparationHydratesDiskBeforeExposingChatRoute() async throws {
        let viewModel = AppViewModel()
        viewModel.config = serverConfig
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        viewModel.localCacheRepository = repository
        try await repository.saveChatMessages(
            [message],
            serverID: serverConfig.recentServerID,
            sessionID: session.id
        )
        viewModel.selectedDirectory = session.directory
        viewModel.allSessions = [session]

        let ticket = viewModel.sessionListFacade.beginSelection(session)
        XCTAssertEqual(viewModel.appShellFacade.detailRoute(isCompact: true), .loadingChat(sessionID: session.id))

        let prepared = await viewModel.sessionListFacade.prepareSelectionForNavigation(ticket)

        XCTAssertTrue(prepared)
        XCTAssertEqual(viewModel.messages, [message])
        XCTAssertEqual(
            viewModel.appShellFacade.detailRoute(isCompact: true),
            .chat(AppShellChatRoute(sessionID: session.id, presentationRequest: 0))
        )
    }

    func testOlderSelectionTicketCannotPrepareAfterNewerNavigationStarts() async throws {
        let viewModel = AppViewModel()
        viewModel.config = serverConfig
        viewModel.localCacheRepository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let newerSession = OpenCodeSession(
            id: "session-newer",
            title: "Newer Session",
            workspaceID: nil,
            directory: session.directory,
            projectID: session.projectID,
            parentID: nil
        )
        viewModel.selectedDirectory = session.directory
        viewModel.allSessions = [session, newerSession]

        let olderTicket = viewModel.sessionListFacade.beginSelection(session)
        _ = viewModel.sessionListFacade.beginSelection(newerSession)

        let prepared = await viewModel.sessionListFacade.prepareSelectionForNavigation(olderTicket)

        XCTAssertFalse(prepared)
        XCTAssertEqual(viewModel.selectedSession?.id, newerSession.id)
    }

    private var serverConfig: OpenCodeServerConfig {
        OpenCodeServerConfig(
            name: "Cache Test",
            baseURL: "https://cache.example",
            username: "opencode",
            password: "password"
        )
    }

    private var project: OpenCodeProject {
        OpenCodeProject(
            id: "project-cache",
            worktree: "/project-cache",
            vcs: "git",
            name: "Cache",
            sandboxes: nil,
            icon: nil,
            time: nil
        )
    }

    private var session: OpenCodeSession {
        OpenCodeSession(
            id: "session-cache",
            title: "Cached Session",
            workspaceID: nil,
            directory: "/project-cache",
            projectID: "project-cache",
            parentID: nil
        )
    }

    private var message: OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope.local(
            role: "assistant",
            text: "Loaded from SwiftData",
            messageID: "message-cache",
            sessionID: session.id,
            partID: "part-cache"
        )
    }

    private var todo: OpenCodeTodo {
        OpenCodeTodo(content: "Verify local cache", status: "in_progress", priority: "high")
    }
}
