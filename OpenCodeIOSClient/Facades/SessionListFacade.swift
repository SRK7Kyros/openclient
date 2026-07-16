import Combine
import Foundation

@MainActor
final class SessionListFacade: ObservableObject {
    struct RowSnapshot: Identifiable, Equatable {
        let session: OpenCodeSession
        let isSelected: Bool
        let showsPinnedBadge: Bool
        let workspaceOverline: String?
        let style: SessionRow.Style
        var preview: SessionPreview?
        var isBusy: Bool
        var hasLiveActivity: Bool
        var hasDraft: Bool
        var hasPermissionRequest: Bool
        var displayTitle: String
        var shimmersTitle: Bool

        var id: String { session.id }
    }

    struct WorkspaceSection: Identifiable, Equatable {
        let directory: String
        let title: String
        let isMain: Bool
        let rows: [RowSnapshot]
        let isLoading: Bool
        let hasMore: Bool
        let operation: OpenCodeWorkspaceOperation?

        var id: String { directory }
        var isBusy: Bool { isLoading || operation?.isBusy == true }
        var isWorkspaceOperationBusy: Bool { operation?.isBusy == true }
    }

    struct ProjectActionSnapshot: Identifiable, Equatable {
        let action: OpenCodeAction
        let command: OpenCodeCommand?
        let phase: OpenCodeActionRunPhase?

        var id: UUID { action.id }
    }

    struct Snapshot: Equatable {
        static let empty = Snapshot(
            isLoadingEmpty: false,
            isEmpty: true,
            selectedSessionID: nil,
            pinnedRows: [],
            unpinnedRows: [],
            showsWorkspaces: false,
            workspaceSections: [],
            errorMessage: nil,
            hasProUnlock: true,
            currentProjectActions: []
        )

        let isLoadingEmpty: Bool
        let isEmpty: Bool
        let selectedSessionID: String?
        let pinnedRows: [RowSnapshot]
        let unpinnedRows: [RowSnapshot]
        let showsWorkspaces: Bool
        let workspaceSections: [WorkspaceSection]
        let errorMessage: String?
        let hasProUnlock: Bool
        let currentProjectActions: [ProjectActionSnapshot]

        var hasBusySession: Bool {
            pinnedRows.contains(where: \.isBusy)
                || unpinnedRows.contains(where: \.isBusy)
                || workspaceSections.contains { $0.rows.contains(where: \.isBusy) }
        }

        var workspaceTaskID: String {
            showsWorkspaces ? workspaceSections.map(\.directory).joined(separator: "|") : "off"
        }
    }

    struct SelectionTicket {
        fileprivate let session: OpenCodeSession
        fileprivate let previousSessionID: String?
    }

    struct CreateSessionSnapshot: Equatable {
        let isPresented: Bool
        let title: String
        let workspaceSelection: NewSessionWorkspaceSelection
        let newWorkspaceName: String
        let projectScopeTitle: String
        let currentProject: OpenCodeProject?
        let workspaceDirectories: [String]
        let showsWorkspacePicker: Bool
        let hasProUnlock: Bool
        let canCreateFreeSession: Bool
        let isLoading: Bool
    }

    private unowned let viewModel: AppViewModel
    @Published private(set) var snapshot = Snapshot.empty
    private var observations: Set<AnyCancellable> = []
    private var activeDirectoryObservations: Set<AnyCancellable> = []
    private var snapshotRefreshTask: Task<Void, Never>?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        snapshot = makeSnapshot()
        Publishers.MergeMany([
            viewModel.sessionListStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.projectStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.projectPreferencesStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.liveActivityStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.commerceFacade.objectWillChange.eraseToAnyPublisher(),
            viewModel.sessionInteractionStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.composerStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.connectionStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.$draftTitle.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$newSessionWorkspaceSelection.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$newWorkspaceName.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingCreateSessionSheet.map { _ in () }.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.scheduleSnapshotRefresh()
        }
        .store(in: &observations)

        bindActiveDirectoryStore(viewModel.directoryStoreRegistry.activeStore)
        viewModel.directoryStoreRegistry.$activeStore
            .dropFirst()
            .sink { [weak self] store in
                self?.bindActiveDirectoryStore(store)
                self?.objectWillChange.send()
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &observations)
    }

    private func makeSnapshot() -> Snapshot {
        let sessions = viewModel.sessions
        let pinnedIDs = viewModel.pinnedSessionIDs
        let showsWorkspaces = viewModel.isProjectWorkspacesEnabled && viewModel.hasGitProject
        let workspaceDirectories = showsWorkspaces ? viewModel.workspaceDirectories() : []
        var sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        for directory in workspaceDirectories {
            for session in viewModel.workspaceSessionsByDirectory[directory]?.rootSessions ?? [] where !viewModel.isActionSession(session) {
                sessionsByID[session.id] = session
            }
        }
        let pinnedSessions = pinnedIDs.compactMap { sessionsByID[$0] }
        let pinnedIDSet = Set(pinnedIDs)
        let unpinnedSessions = showsWorkspaces ? [] : sessions.filter { !pinnedIDSet.contains($0.id) }

        return Snapshot(
            isLoadingEmpty: viewModel.isLoadingSessions && sessions.isEmpty,
            isEmpty: sessions.isEmpty,
            selectedSessionID: viewModel.selectedSession?.id,
            pinnedRows: pinnedSessions.map {
                rowSnapshot(
                    for: $0,
                    showsPinnedBadge: true,
                    workspaceOverline: showsWorkspaces ? viewModel.workspaceDisplayName(for: $0.directory) : nil
                )
            },
            unpinnedRows: unpinnedSessions.map { rowSnapshot(for: $0) },
            showsWorkspaces: showsWorkspaces,
            workspaceSections: showsWorkspaces
                ? workspaceSections(directories: workspaceDirectories, excluding: pinnedIDSet)
                : [],
            errorMessage: isScreenshotScene ? nil : viewModel.errorMessage,
            hasProUnlock: viewModel.commerceFacade.hasProUnlock,
            currentProjectActions: viewModel.currentProjectActions.map { action in
                ProjectActionSnapshot(
                    action: action,
                    command: viewModel.actionCommand(for: action),
                    phase: viewModel.actionRunPhase(for: action)
                )
            }
        )
    }

    private func scheduleSnapshotRefresh() {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            let nextSnapshot = makeSnapshot()
            if snapshot != nextSnapshot {
                snapshot = nextSnapshot
            }
            snapshotRefreshTask = nil
        }
    }

    var remainingFreePromptsToday: Int { viewModel.commerceFacade.remainingFreePromptsToday }
    var remainingFreeSessions: Int { viewModel.commerceFacade.remainingFreeSessions }

    var createSessionSnapshot: CreateSessionSnapshot {
        CreateSessionSnapshot(
            isPresented: viewModel.isShowingCreateSessionSheet,
            title: viewModel.draftTitle,
            workspaceSelection: viewModel.newSessionWorkspaceSelection,
            newWorkspaceName: viewModel.newWorkspaceName,
            projectScopeTitle: viewModel.projectScopeTitle,
            currentProject: viewModel.currentProject,
            workspaceDirectories: viewModel.workspaceDirectories(),
            showsWorkspacePicker: viewModel.isProjectWorkspacesEnabled && viewModel.hasGitProject,
            hasProUnlock: viewModel.commerceFacade.hasProUnlock,
            canCreateFreeSession: viewModel.canCreateFreeSession,
            isLoading: viewModel.isLoading
        )
    }

    var createSessionTitle: String {
        get { viewModel.draftTitle }
        set { viewModel.draftTitle = newValue }
    }

    var newSessionWorkspaceSelection: NewSessionWorkspaceSelection {
        get { viewModel.newSessionWorkspaceSelection }
        set { viewModel.newSessionWorkspaceSelection = newValue }
    }

    var newWorkspaceName: String {
        get { viewModel.newWorkspaceName }
        set { viewModel.newWorkspaceName = newValue }
    }

    func dismissCreateSession() { viewModel.isShowingCreateSessionSheet = false }
    func workspaceTitle(for selection: NewSessionWorkspaceSelection) -> String {
        viewModel.newSessionWorkspaceTitle(for: selection)
    }
    func createSession() async { await viewModel.createSession() }
    func presentSessionLimitPaywall() {
        dismissCreateSession()
        viewModel.commerceFacade.presentPaywall(reason: .sessionLimit)
    }

    func presentPaywall(reason: OpenClientPaywallReason) {
        viewModel.commerceFacade.presentPaywall(reason: reason)
    }

    func refresh() async {
        await viewModel.refreshSessionList()
    }

    func beginSelection(_ session: OpenCodeSession) -> SelectionTicket {
        SelectionTicket(session: session, previousSessionID: viewModel.beginSessionNavigation(session))
    }

    func completeSelection(_ ticket: SelectionTicket) async {
        await Task.yield()
        guard prepareSelectionIfCurrent(ticket) else { return }
        await viewModel.selectSession(ticket.session)
    }

    @discardableResult
    func prepareSelectionIfCurrent(_ ticket: SelectionTicket) -> Bool {
        guard viewModel.selectedSession?.id == ticket.session.id else { return false }
        viewModel.prepareSessionSelection(
            ticket.session,
            preservingDraftForSessionID: ticket.previousSessionID,
            animatesChanges: false
        )
        return viewModel.selectedSession?.id == ticket.session.id
    }

    func isPinned(_ session: OpenCodeSession) -> Bool { viewModel.isSessionPinned(session) }
    func pin(_ session: OpenCodeSession) { viewModel.pinSession(session) }
    func unpin(_ session: OpenCodeSession) { viewModel.unpinSession(session) }

    func movePinnedSessions(from offsets: IndexSet, to destination: Int) {
        viewModel.movePinnedSessions(fromOffsets: offsets, toOffset: destination)
    }

    func rename(_ session: OpenCodeSession, title: String) async { await viewModel.renameSession(session, title: title) }
    func delete(_ session: OpenCodeSession) async { await viewModel.deleteSession(session) }
    func toggleLiveActivity(for session: OpenCodeSession) async { await viewModel.liveActivityFacade.toggle(session: session) }
    func isLiveActivityActive(for session: OpenCodeSession) -> Bool { viewModel.liveActivityFacade.isActive(sessionID: session.id) }
    func runAction(_ action: OpenCodeAction) async { await viewModel.runAction(action) }
    func createWorkspace(name: String) async { await viewModel.createWorkspace(name: name) }
    func loadWorkspaceSessionsIfNeeded() async { await viewModel.loadWorkspaceSessionsIfNeeded() }
    func loadMoreWorkspaceSessions(directory: String) async { await viewModel.loadMoreWorkspaceSessions(directory: directory) }
    func presentNewSession(inWorkspace directory: String) { viewModel.presentNewSession(inWorkspace: directory) }
    func refreshWorkspaceSessions(directory: String) async { await viewModel.refreshWorkspaceSessions(directory: directory) }
    func resetWorktree(directory: String) async { await viewModel.resetWorktree(directory: directory) }
    func deleteWorktree(directory: String) async { await viewModel.deleteWorktree(directory: directory) }

    private func workspaceSections(
        directories: [String],
        excluding pinnedIDSet: Set<String>
    ) -> [WorkspaceSection] {
        directories.map { directory in
            let state = viewModel.workspaceSessionsByDirectory[directory] ?? OpenCodeWorkspaceSessionState()
            let sessions = state.rootSessions.filter { !pinnedIDSet.contains($0.id) && !viewModel.isActionSession($0) }
            return WorkspaceSection(
                directory: directory,
                title: viewModel.workspaceDisplayName(for: directory) ?? URL(fileURLWithPath: directory).lastPathComponent,
                isMain: viewModel.currentProject.map { viewModel.workspaceKey($0.worktree) == viewModel.workspaceKey(directory) } ?? false,
                rows: sessions.map { rowSnapshot(for: $0) },
                isLoading: state.isLoading,
                hasMore: state.hasMore,
                operation: viewModel.sessionListStore.workspaceOperation(for: directory)
            )
        }
    }

    private func rowSnapshot(
        for session: OpenCodeSession,
        showsPinnedBadge: Bool = false,
        workspaceOverline: String? = nil
    ) -> RowSnapshot {
        RowSnapshot(
            session: session,
            isSelected: viewModel.selectedSession?.id == session.id,
            showsPinnedBadge: showsPinnedBadge,
            workspaceOverline: workspaceOverline,
            style: .regular,
            preview: viewModel.sessionPreviews[session.id],
            isBusy: viewModel.sessionStatuses[session.id] == "busy",
            hasLiveActivity: viewModel.isLiveActivityActive(for: session),
            hasDraft: viewModel.hasMessageDraft(for: session),
            hasPermissionRequest: viewModel.hasPermissionRequest(for: session),
            displayTitle: session.displayTitle(),
            shimmersTitle: session.isDefaultGeneratedTitle
        )
    }

    private var isScreenshotScene: Bool {
        ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] != nil
    }

    private func bindActiveDirectoryStore(_ store: DirectoryStore) {
        activeDirectoryObservations.removeAll()
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &activeDirectoryObservations)
    }
}
