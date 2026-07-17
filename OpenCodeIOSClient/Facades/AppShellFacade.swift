import Combine
import Foundation
import SwiftUI

enum AppShellPrimarySheet: Identifiable, Equatable {
    case connection
    case newProjectChat(NewProjectChatSheetRequest)

    var id: String {
        switch self {
        case .connection:
            return "connection"
        case let .newProjectChat(request):
            return "newProjectChat-\(request.id.uuidString)"
        }
    }

    static func == (lhs: AppShellPrimarySheet, rhs: AppShellPrimarySheet) -> Bool {
        switch (lhs, rhs) {
        case (.connection, .connection):
            return true
        case let (.newProjectChat(lhsRequest), .newProjectChat(rhsRequest)):
            return lhsRequest.id == rhsRequest.id
        default:
            return false
        }
    }
}

enum AppShellContentRoute: Equatable {
    case selectProject
    case loadingProject
    case projectContent
}

struct AppShellChatRoute: Equatable {
    let sessionID: String
    let presentationRequest: Int
}

enum AppShellDetailRoute: Equatable {
    case gitFile
    case gitDiff
    case mcp
    case loadingChat(sessionID: String)
    case chat(AppShellChatRoute)
    case selectSession
}

@MainActor
final class AppShellFacade: ObservableObject {
    struct ProjectContentSnapshot: Equatable {
        let selectedTab: OpenClientProjectContentTab
        let availableTabs: [OpenClientProjectContentTab]
        let title: String
        let isShowingSettings: Bool
        let hasGitProject: Bool
        let filesMode: OpenCodeProjectFilesMode
        let isLoadingVCS: Bool
        let isLoadingFileTree: Bool
        let isLoadingMCP: Bool
        let currentProjectID: String?
        let effectiveSelectedDirectory: String?

        var toolbarIcon: String {
            switch selectedTab {
            case .sessions:
                return "square.and.pencil"
            case .git, .mcp:
                return "arrow.clockwise"
            }
        }

        var toolbarLabel: String {
            switch selectedTab {
            case .sessions:
                return "Create Session"
            case .git:
                return filesMode == .tree ? "Refresh File Tree" : "Refresh Files"
            case .mcp:
                return "Refresh MCP Servers"
            }
        }

        var toolbarIdentifier: String {
            switch selectedTab {
            case .sessions:
                return "sessions.create"
            case .git:
                return "git.refresh"
            case .mcp:
                return "mcp.refresh"
            }
        }

        var isToolbarDisabled: Bool {
            switch selectedTab {
            case .sessions:
                return false
            case .git:
                return isLoadingVCS || isLoadingFileTree
            case .mcp:
                return isLoadingMCP
            }
        }

        func showsToolbarAction(usesNativeComposeTab: Bool) -> Bool {
            selectedTab != .sessions || !usesNativeComposeTab
        }
    }

    let connection: ConnectionFacade
    let commerce: CommerceFacade
    let projects: ProjectFacade
    let newProjectChat: NewProjectChatFacade
    let sessions: SessionListFacade
    let projectFiles: ProjectFilesFacade
    let mcp: MCPFacade
    let configurations: ConfigurationsFacade
    let funAndGames: FunAndGamesFacade
    let chat: ChatFacade

    private unowned let viewModel: AppViewModel
    private var observations: Set<AnyCancellable> = []
    private var activeDirectoryObservations: Set<AnyCancellable> = []

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        connection = viewModel.connectionFacade
        commerce = viewModel.commerceFacade
        projects = viewModel.projectFacade
        newProjectChat = viewModel.newProjectChatFacade
        sessions = viewModel.sessionListFacade
        projectFiles = viewModel.projectFilesFacade
        mcp = viewModel.mcpFacade
        configurations = viewModel.configurationsFacade
        funAndGames = viewModel.funAndGamesFacade
        chat = viewModel.chatFacade

        Publishers.MergeMany([
            viewModel.connectionStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.projectStore.objectWillChange.eraseToAnyPublisher(),
            commerce.objectWillChange.eraseToAnyPublisher(),
            projectFiles.objectWillChange.eraseToAnyPublisher(),
            mcp.objectWillChange.eraseToAnyPublisher(),
            viewModel.chatStore.$preparedSessionID.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingConnectionOverlay.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$newProjectChatSheetRequest.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingProjectSettingsSheet.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$openURLNavigationMessage.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$chatDetailPresentationRequest.map { _ in () }.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &observations)

        bindActiveDirectoryStore(viewModel.directoryStoreRegistry.activeStore)
        viewModel.directoryStoreRegistry.$activeStore
            .dropFirst()
            .sink { [weak self] store in
                self?.bindActiveDirectoryStore(store)
                self?.objectWillChange.send()
            }
            .store(in: &observations)
    }

    var primarySheet: AppShellPrimarySheet? {
        if let request = viewModel.newProjectChatSheetRequest {
            return .newProjectChat(request)
        }
        if showsConnectionSheetContent {
            return .connection
        }
        return nil
    }

    var showsConnectionSheetContent: Bool {
        !connection.isConnected || connection.isUsingAppleIntelligence || connection.isShowingConnectionOverlay
    }

    var hidesShellForConnectionExperience: Bool {
        !connection.isConnected || connection.isShowingConnectionOverlay
    }

    var openURLNavigationMessage: String? { viewModel.openURLNavigationMessage }
    var isConnected: Bool { connection.isConnected }
    var isShowingConnectionOverlay: Bool { connection.isShowingConnectionOverlay }
    var hasActiveWorkspace: Bool { viewModel.hasActiveWorkspace }
    var currentProjectID: String? { projects.currentProject?.id }
    var hasCurrentProject: Bool { projects.currentProject != nil }
    var selectedSessionID: String? { viewModel.directoryStoreRegistry.activeStore.selectedSession?.id }
    var chatDetailPresentationRequest: Int { viewModel.chatDetailPresentationRequest }

    var projectContentSnapshot: ProjectContentSnapshot {
        let files = projectFiles.snapshot
        let selectedTab = viewModel.projectStore.selectedContentTab
        let scopeTitle = viewModel.projectScopeTitle
        return ProjectContentSnapshot(
            selectedTab: selectedTab,
            availableTabs: OpenClientProjectContentTab.allCases.filter { $0 != .git || projectFiles.hasGitProject },
            title: scopeTitle.split(separator: "/").last.map(String.init) ?? scopeTitle,
            isShowingSettings: projects.isShowingProjectSettingsSheet,
            hasGitProject: projectFiles.hasGitProject,
            filesMode: files.filesMode,
            isLoadingVCS: files.isLoadingVCS,
            isLoadingFileTree: files.isLoadingFileTree,
            isLoadingMCP: mcp.snapshot.isLoading,
            currentProjectID: projects.currentProject?.id,
            effectiveSelectedDirectory: viewModel.effectiveSelectedDirectory
        )
    }

    func contentRoute(isCompact: Bool) -> AppShellContentRoute {
        guard projects.currentProject != nil else { return .selectProject }
        let directory = viewModel.directoryStoreRegistry.activeStore
        if isCompact, directory.isLoadingSessions, directory.sessions.isEmpty {
            return .loadingProject
        }
        return .projectContent
    }

    func detailRoute(isCompact: Bool) -> AppShellDetailRoute {
        let projectContent = projectContentSnapshot
        if projectContent.selectedTab == .git, projectContent.hasGitProject {
            return projectFiles.snapshot.selectedFileIsChanged ? .gitDiff : .gitFile
        }
        if projectContent.selectedTab == .mcp {
            return .mcp
        }

        let directory = viewModel.directoryStoreRegistry.activeStore
        guard let session = directory.selectedSession, !connection.isUsingAppleIntelligence else {
            return .selectSession
        }
        if viewModel.chatStore.preparedSessionID != session.id {
            return .loadingChat(sessionID: session.id)
        }
        return .chat(
            AppShellChatRoute(
                sessionID: session.id,
                presentationRequest: viewModel.chatDetailPresentationRequest
            )
        )
    }

    func dismissPrimarySheet() {
        guard viewModel.newProjectChatSheetRequest != nil else { return }
        projects.dismissNewChat()
    }

    func setProjectSettingsPresented(_ isPresented: Bool) {
        projects.isShowingProjectSettingsSheet = isPresented
    }

    func presentProjectSettings() {
        projects.presentSettings()
    }

    func selectProjectContentTab(_ tab: OpenClientProjectContentTab) {
        switch tab {
        case .sessions:
            viewModel.selectedProjectContentTab = .sessions
        case .git:
            guard projectFiles.hasGitProject else { return }
            viewModel.preserveCurrentMessageDraftForNavigation()
            projectFiles.prepareForPresentation()
            withAnimation(opencodeSelectionAnimation) {
                viewModel.selectedProjectContentTab = .git
                viewModel.selectedSession = nil
            }

            Task { [projectFiles] in
                await projectFiles.loadGitViewDataIfNeeded()
                if projectFiles.snapshot.filesMode == .tree {
                    await projectFiles.loadFileTreeIfNeeded()
                }
            }
        case .mcp:
            viewModel.preserveCurrentMessageDraftForNavigation()
            withAnimation(opencodeSelectionAnimation) {
                viewModel.selectedProjectContentTab = .mcp
                viewModel.selectedSession = nil
            }

            Task { [mcp] in
                await mcp.loadIfNeeded()
            }
        }
    }

    func reconcileInvalidGitSelection() {
        guard !projectFiles.hasGitProject, viewModel.selectedProjectContentTab == .git else { return }
        viewModel.selectedProjectContentTab = .sessions
    }

    func presentNewChat(
        projectID: String?,
        workspaceDirectory: String?,
        locksProject: Bool
    ) {
        viewModel.presentNewProjectChatSheet(
            projectID: projectID,
            workspaceDirectory: workspaceDirectory,
            locksProject: locksProject
        )
    }

    func presentNewChatForCurrentContext() {
        presentNewChat(
            projectID: viewModel.currentProject?.id,
            workspaceDirectory: viewModel.effectiveSelectedDirectory,
            locksProject: true
        )
    }

    func performProjectContentToolbarAction() {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            presentNewChatForCurrentContext()
        case .git:
            Task { [projectFiles] in
                await projectFiles.refresh()
            }
        case .mcp:
            Task { [mcp] in
                await mcp.reload()
            }
        }
    }

    func prepareOpenURLPresentation(_ url: URL) {
        viewModel.prepareOpenURLPresentation(url)
    }

    func handleOpenURL(_ url: URL) async {
        await viewModel.handleOpenURL(url)
    }

    func scheduleForegroundChatCatchUp(reason: String) {
        viewModel.scheduleForegroundChatCatchUp(reason: reason)
    }

    private func bindActiveDirectoryStore(_ store: DirectoryStore) {
        activeDirectoryObservations.removeAll()
        store.objectWillChange
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &activeDirectoryObservations)
    }
}
