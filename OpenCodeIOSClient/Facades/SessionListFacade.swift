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
        var projectTitle: String
        var projectIcon: OpenCodeProject.Icon?
        var usesGlobalProjectAvatar: Bool
        var activityNeedsInput: Bool
        var activityIsWorking: Bool
        var activityStatusTitle: String
        var latestUserText: String?
        var latestAssistantText: String?
        var runningTools: [ActivityFacade.ToolSnapshot]
        var updatedAt: Date?
        var pendingInteractionCount: Int
        var completedTodoCount: Int
        var todoCount: Int

        var id: String { session.id }

        var activityRow: ActivityFacade.RowSnapshot {
            var displaySession = OpenCodeSession(
                id: session.id,
                title: displayTitle,
                workspaceID: session.workspaceID,
                directory: session.directory,
                projectID: session.projectID,
                parentID: session.parentID
            )
            displaySession.time = session.time
            return ActivityFacade.RowSnapshot(
                recent: RecentProjectSession(
                    session: displaySession,
                    projectTitle: projectTitle,
                    preview: preview,
                    isBusy: activityIsWorking
                ),
                projectID: session.projectID ?? session.directory ?? "global",
                projectIcon: projectIcon,
                usesGlobalProjectAvatar: usesGlobalProjectAvatar,
                needsInput: activityNeedsInput,
                isWorking: activityIsWorking,
                statusTitle: activityStatusTitle,
                latestUserText: latestUserText,
                latestAssistantText: latestAssistantText,
                runningTools: runningTools,
                updatedAt: updatedAt,
                latestUserMessageAt: nil,
                pendingInteractionCount: pendingInteractionCount,
                completedTodoCount: completedTodoCount,
                todoCount: todoCount,
                isLiveActivityActive: hasLiveActivity,
                isHydrating: false,
                hydrationGeneration: 0
            )
        }
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
            isLoadingMoreSessions: false,
            isEmpty: true,
            selectedSessionID: nil,
            pinnedRows: [],
            unpinnedRows: [],
            showsWorkspaces: false,
            workspaceSections: [],
            hasMoreSessions: false,
            errorMessage: nil,
            hasProUnlock: true,
            isReadOnly: false,
            cardStyle: .simple,
            showsActivityLastUserMessage: true,
            currentProjectActions: []
        )

        let isLoadingEmpty: Bool
        let isLoadingMoreSessions: Bool
        let isEmpty: Bool
        let selectedSessionID: String?
        let pinnedRows: [RowSnapshot]
        let unpinnedRows: [RowSnapshot]
        let showsWorkspaces: Bool
        let workspaceSections: [WorkspaceSection]
        let hasMoreSessions: Bool
        let errorMessage: String?
        let hasProUnlock: Bool
        let isReadOnly: Bool
        let cardStyle: SessionCardStyle
        let showsActivityLastUserMessage: Bool
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
        fileprivate let navigationGeneration: UInt
        fileprivate let directoryKey: String
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
    private weak var liveActivityBackgroundBridge: LiveActivityBackgroundBridge?
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
            viewModel.appCustomizationStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.$draftTitle.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$newSessionWorkspaceSelection.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$newWorkspaceName.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingCreateSessionSheet.map { _ in () }.eraseToAnyPublisher(),
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.scheduleSnapshotRefresh()
        }
        .store(in: &observations)

        bindActiveDirectoryStore(viewModel.directoryStoreRegistry.activeStore)
        viewModel.directoryStoreRegistry.$activeStore
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] store in
                self?.bindActiveDirectoryStore(store)
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &observations)
    }

    func attachLiveActivityBackgroundBridge(_ bridge: LiveActivityBackgroundBridge) {
        liveActivityBackgroundBridge = bridge
    }

    private func makeSnapshot() -> Snapshot {
        var sessions: [OpenCodeSession] = []
        var sessionIndexByID: [String: Int] = [:]
        for session in viewModel.sessions {
            if let index = sessionIndexByID[session.id] {
                sessions[index] = sessions[index].merged(with: session)
            } else {
                sessionIndexByID[session.id] = sessions.count
                sessions.append(session)
            }
        }
        let pinnedIDs = viewModel.pinnedSessionIDs
        let isReadOnly = viewModel.isBrowsingLocalCache
        let showsWorkspaces = !isReadOnly && viewModel.isProjectWorkspacesEnabled && viewModel.hasGitProject
        let workspaceDirectories = showsWorkspaces ? viewModel.workspaceDirectories() : []
        var sessionsByID: [String: OpenCodeSession] = [:]
        for session in sessions {
            sessionsByID[session.id] = session
        }
        for directory in workspaceDirectories {
            for session in viewModel.workspaceSessionsByDirectory[directory]?.rootSessions ?? [] where !viewModel.isActionSession(session) {
                sessionsByID[session.id] = session
            }
        }
        let permissionRootIDs = SessionInteractionStore.sessionTreeRootIDsWithRequests(
            sessions: viewModel.allSessions,
            requestsBySessionID: viewModel.directoryStore.syncState.permissionsBySessionID
        )
        let pinnedSessions = pinnedIDs.compactMap { sessionsByID[$0] }
        let pinnedIDSet = Set(pinnedIDs)
        let unpinnedSessions = showsWorkspaces ? [] : sessions.filter { !pinnedIDSet.contains($0.id) }

        return Snapshot(
            isLoadingEmpty: viewModel.isLoadingSessions && sessions.isEmpty,
            isLoadingMoreSessions: viewModel.isLoadingSessions && !sessions.isEmpty,
            isEmpty: sessions.isEmpty,
            selectedSessionID: viewModel.selectedSession?.id,
            pinnedRows: pinnedSessions.map {
                rowSnapshot(
                    for: $0,
                    showsPinnedBadge: true,
                    workspaceOverline: showsWorkspaces ? viewModel.workspaceDisplayName(for: $0.directory) : nil,
                    hasPermissionRequest: showsWorkspaces ? nil : permissionRootIDs.contains($0.id)
                )
            },
            unpinnedRows: unpinnedSessions.map {
                rowSnapshot(for: $0, hasPermissionRequest: permissionRootIDs.contains($0.id))
            },
            showsWorkspaces: showsWorkspaces,
            workspaceSections: showsWorkspaces
                ? workspaceSections(directories: workspaceDirectories, excluding: pinnedIDSet)
                : [],
            hasMoreSessions: !showsWorkspaces && viewModel.directoryStore.hasMoreSessions,
            errorMessage: isScreenshotScene ? nil : viewModel.errorMessage,
            hasProUnlock: viewModel.commerceFacade.hasProUnlock,
            isReadOnly: isReadOnly,
            cardStyle: viewModel.appCustomizationStore.sessionCardStyle,
            showsActivityLastUserMessage: viewModel.appCustomizationStore.showsActivityLastUserMessage,
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
    func createSession() async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.createSession()
    }
    func presentSessionLimitPaywall() {
        dismissCreateSession()
        viewModel.commerceFacade.presentPaywall(reason: .sessionLimit)
    }

    func presentPaywall(reason: OpenClientPaywallReason) {
        viewModel.commerceFacade.presentPaywall(reason: reason)
    }

    func refresh() async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.refreshSessionList()
    }

    func prepareActivityCardsIfNeeded() async {
        guard viewModel.appCustomizationStore.sessionCardStyle == .activity else { return }
        await viewModel.activityFacade.prepareForPresentation()
    }

    func loadMoreSessions() async {
        await viewModel.loadMoreSessions()
    }

    func beginSelection(_ session: OpenCodeSession) -> SelectionTicket {
        let previousSessionID = viewModel.beginSessionNavigation(session)
        return SelectionTicket(
            session: session,
            previousSessionID: previousSessionID,
            navigationGeneration: viewModel.sessionNavigationGeneration,
            directoryKey: viewModel.directoryStoreRegistry.activeKey
        )
    }

    func completeSelection(_ ticket: SelectionTicket) async {
        guard selectionIsCurrent(ticket) else { return }
        await viewModel.selectSession(ticket.session)
    }

    func prepareSelectionForNavigation(_ ticket: SelectionTicket) async -> Bool {
        guard prepareSelectionIfCurrent(ticket) else { return false }
        guard !viewModel.hasHydratedLocalChat(sessionID: ticket.session.id) else { return true }

        if await viewModel.hydrateChatFromLocalCache(
            ticket.session,
            navigationGeneration: ticket.navigationGeneration,
            expectedDirectoryKey: ticket.directoryKey
        ) != nil {
            guard prepareSelectionIfCurrent(ticket) else { return false }
        }
        return selectionIsCurrent(ticket)
    }

    @discardableResult
    func prepareSelectionIfCurrent(_ ticket: SelectionTicket) -> Bool {
        guard selectionIsCurrent(ticket) else { return false }
        viewModel.prepareSessionSelection(
            ticket.session,
            preservingDraftForSessionID: ticket.previousSessionID,
            animatesChanges: false
        )
        return selectionIsCurrent(ticket)
    }

    private func selectionIsCurrent(_ ticket: SelectionTicket) -> Bool {
        viewModel.isSessionNavigationCurrent(
            sessionID: ticket.session.id,
            generation: ticket.navigationGeneration,
            directoryKey: ticket.directoryKey
        )
    }

    func isPinned(_ session: OpenCodeSession) -> Bool { viewModel.isSessionPinned(session) }
    func pin(_ session: OpenCodeSession) { viewModel.pinSession(session) }
    func unpin(_ session: OpenCodeSession) { viewModel.unpinSession(session) }

    func movePinnedSessions(from offsets: IndexSet, to destination: Int) {
        viewModel.movePinnedSessions(fromOffsets: offsets, toOffset: destination)
    }

    func rename(_ session: OpenCodeSession, title: String) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.renameSession(session, title: title)
    }
    func delete(_ session: OpenCodeSession) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        if await viewModel.deleteSession(session) {
            liveActivityBackgroundBridge?.cancel(sessionID: session.id, reason: "Session deleted")
        }
    }
    func toggleLiveActivity(for session: OpenCodeSession) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.liveActivityFacade.toggle(session: session)
    }
    func isLiveActivityActive(for session: OpenCodeSession) -> Bool { viewModel.liveActivityFacade.isActive(sessionID: session.id) }
    func runAction(_ action: OpenCodeAction) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.runAction(action)
    }
    func createWorkspace(name: String) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.createWorkspace(name: name)
    }
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
        workspaceOverline: String? = nil,
        hasPermissionRequest: Bool? = nil
    ) -> RowSnapshot {
        let generatedTitle = session.defaultGeneratedTitleDisplayName
        let isBusy = viewModel.sessionStatuses[session.id] == "busy"
        let directorySnapshot = viewModel.directoryStoreRegistry.snapshot(forSessionID: session.id)
        let messages = directorySnapshot?.messages ?? []
        let status = directorySnapshot?.status ?? viewModel.sessionStatuses[session.id]
        let isWorking = status.map { $0 != "idle" } ?? false
        let todos = directorySnapshot?.todos ?? []
        let permissionCount = directorySnapshot?.permissions.count ?? 0
        let questionCount = directorySnapshot?.questions.count ?? 0
        let project = viewModel.currentProject
        return RowSnapshot(
            session: session,
            isSelected: viewModel.selectedSession?.id == session.id,
            showsPinnedBadge: showsPinnedBadge,
            workspaceOverline: workspaceOverline,
            style: .regular,
            preview: viewModel.sessionPreviews[session.id],
            isBusy: isBusy,
            hasLiveActivity: viewModel.isLiveActivityActive(for: session),
            hasDraft: viewModel.hasMessageDraft(for: session),
            hasPermissionRequest: hasPermissionRequest ?? viewModel.hasPermissionRequest(for: session),
            displayTitle: generatedTitle ?? session.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Untitled Session"),
            shimmersTitle: generatedTitle != nil && isBusy,
            projectTitle: projectTitle(project),
            projectIcon: project?.icon,
            usesGlobalProjectAvatar: project?.id == "global" || session.isGlobalScopeSession,
            activityNeedsInput: permissionCount + questionCount > 0,
            activityIsWorking: isWorking,
            activityStatusTitle: activityStatusTitle(
                status: status,
                permissionCount: permissionCount,
                questionCount: questionCount
            ),
            latestUserText: activityLatestText(in: messages, role: "user"),
            latestAssistantText: activityLatestText(in: messages, role: "assistant") ?? viewModel.sessionPreviews[session.id]?.text,
            runningTools: activityRunningToolSnapshots(in: messages),
            updatedAt: (session.time?.updated ?? session.time?.created).map { Date(timeIntervalSince1970: $0 / 1_000) }
                ?? viewModel.sessionPreviews[session.id]?.date,
            pendingInteractionCount: permissionCount + questionCount,
            completedTodoCount: todos.lazy.filter { $0.status == "completed" }.count,
            todoCount: todos.count
        )
    }

    private func projectTitle(_ project: OpenCodeProject?) -> String {
        guard let project else { return String(localized: "Project") }
        if let name = project.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if project.id == "global" { return String(localized: "Global") }
        let title = URL(fileURLWithPath: project.worktree).lastPathComponent
        return title.isEmpty ? project.id : title
    }

    private func activityLatestText(in messages: [OpenCodeMessageEnvelope], role: String) -> String? {
        for message in messages.reversed() where message.info.role?.lowercased() == role {
            let textParts = message.parts.filter { $0.type == "text" }.compactMap(\.text)
            let fallbackParts = message.parts.filter { $0.type == "reasoning" }.compactMap(\.text)
            if let text = opencodePreviewText((textParts.isEmpty ? fallbackParts : textParts).joined(separator: " "), limit: nil) {
                return text
            }
        }
        return nil
    }

    private func activityStatusTitle(status: String?, permissionCount: Int, questionCount: Int) -> String {
        if permissionCount + questionCount > 0 { return String(localized: "Needs input") }
        switch status?.lowercased() {
        case "busy", "running", "working", "pending", "in_progress":
            return String(localized: "Working")
        default:
            return String(localized: "Idle")
        }
    }

    private func activityRunningToolSnapshots(in messages: [OpenCodeMessageEnvelope]) -> [ActivityFacade.ToolSnapshot] {
        guard let message = messages.last,
              let part = message.parts.last,
              let tool = part.tool,
              ["running", "pending", "in_progress"].contains(part.state?.status?.lowercased() ?? "") else { return [] }
        let id = part.id ?? part.callID ?? "\(message.id):\(tool)"
        let title = activityToolTitle(part: part, tool: tool)
        let input = part.state?.input
        var detail: String? = input?.command
        if detail == nil { detail = input?.description }
        if detail == nil { detail = input?.filePath }
        if detail == nil { detail = input?.path }
        if detail == nil { detail = input?.query }
        if detail == nil { detail = input?.pattern }

        return [
            ActivityFacade.ToolSnapshot(
                id: id,
                tool: tool,
                title: title,
                detail: detail
            ),
        ]
    }

    private func activityToolTitle(part: OpenCodePart, tool: String) -> String {
        if let title = part.state?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return tool.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var isScreenshotScene: Bool {
        ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] != nil
    }

    private func bindActiveDirectoryStore(_ store: DirectoryStore) {
        activeDirectoryObservations.removeAll()
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSnapshotRefresh()
            }
            .store(in: &activeDirectoryObservations)
    }
}
