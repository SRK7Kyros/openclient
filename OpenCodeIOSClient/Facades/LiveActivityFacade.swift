import Combine
import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

@MainActor
final class LiveActivityFacade: ObservableObject {
    private static let refreshDelay: Duration = .milliseconds(350)

    private unowned let viewModel: AppViewModel
    private weak var liveActivityBackgroundBridge: LiveActivityBackgroundBridge?
    private var observations: Set<AnyCancellable> = []

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        Publishers.MergeMany([
            viewModel.liveActivityStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.directoryStoreRegistry.objectWillChange.eraseToAnyPublisher(),
            viewModel.sessionListStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.sessionInteractionStore.objectWillChange.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &observations)
    }

    func attachLiveActivityBackgroundBridge(_ bridge: LiveActivityBackgroundBridge) {
        liveActivityBackgroundBridge = bridge
    }

    var activeSessionIDs: Set<String> { viewModel.activeLiveActivitySessionIDs }

    func isActive(sessionID: String) -> Bool {
        activeSessionIDs.contains(sessionID)
    }

    func toggle(session: OpenCodeSession) async {
        if isActive(sessionID: session.id) {
            await stop(sessionID: session.id, immediate: true)
        } else {
            await start(session: session)
        }
    }

    func start(session: OpenCodeSession, userVisibleErrors: Bool = true) async {
        #if canImport(ActivityKit) && os(iOS)
        do {
            let state = state(for: session)
            let config = viewModel.config
            try await LiveActivityCoordinator.requestOrUpdate(
                LiveActivityStartRequest(
                    sessionID: session.id,
                    sessionTitle: sessionTitle(for: session),
                    credentialID: config.recentServerID,
                    serverBaseURL: config.baseURL,
                    serverUsername: config.username,
                    directory: session.isGlobalScopeSession ? nil : session.directory,
                    workspaceID: session.workspaceID,
                    state: state
                )
            )
            viewModel.activeLiveActivitySessionIDs.insert(session.id)
            viewModel.liveActivityStore.setLastState(state, for: session.id)
            if userVisibleErrors {
                viewModel.errorMessage = nil
            }
        } catch {
            if userVisibleErrors {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    func autoStartIfEnabled(session: OpenCodeSession) async {
        guard viewModel.isConnected,
              !viewModel.isUsingAppleIntelligence,
              viewModel.isLiveActivityAutoStartEnabled else { return }
        guard !isActive(sessionID: session.id) else { return }
        await start(session: session, userVisibleErrors: false)
    }

    func reconcile() {
        #if canImport(ActivityKit) && os(iOS)
        viewModel.activeLiveActivitySessionIDs.formUnion(LiveActivityCoordinator.activeSessionIDs())
        for (sessionID, state) in LiveActivityCoordinator.currentStatesBySessionID() {
            viewModel.liveActivityStore.setLastState(state, for: sessionID)
        }
        #endif
    }

    func stop(sessionID: String, immediate: Bool = false) async {
        #if canImport(ActivityKit) && os(iOS)
        viewModel.liveActivityStore.cancelRefresh(for: sessionID)
        viewModel.liveActivityStore.cancelPreviewRefresh(for: sessionID)
        let session = sessionSnapshot(for: sessionID)
        if let finalState = session.map({ state(for: $0) }) ?? viewModel.liveActivityStore.lastState(for: sessionID) {
            await LiveActivityCoordinator.end(sessionID: sessionID, state: finalState, immediate: immediate)
        }
        viewModel.activeLiveActivitySessionIDs.remove(sessionID)
        viewModel.liveActivityStore.setLastState(nil, for: sessionID)
        liveActivityBackgroundBridge?.cancel(sessionID: sessionID, reason: "Live Activity stopped")
        #endif
    }

    func stopAll(immediate: Bool = true) async {
        for sessionID in activeSessionIDs {
            await stop(sessionID: sessionID, immediate: immediate)
        }
    }

    func refresh(sessionID: String? = nil, endIfIdle: Bool = false, immediate: Bool = false) {
        #if canImport(ActivityKit) && os(iOS)
        if let sessionID, !immediate, !endIfIdle {
            guard isActive(sessionID: sessionID) else { return }
            guard LiveActivitySnapshotBuilder.shouldScheduleRefresh(
                pendingRefreshExists: viewModel.liveActivityStore.hasPendingRefresh(for: sessionID),
                immediate: immediate,
                endIfIdle: endIfIdle
            ) else { return }
            viewModel.liveActivityStore.setRefreshTask(Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.refreshDelay)
                guard !Task.isCancelled else { return }
                self?.refresh(sessionID: sessionID, endIfIdle: endIfIdle, immediate: true)
                self?.viewModel.liveActivityStore.clearRefreshTask(for: sessionID)
            }, for: sessionID)
            return
        }

        if sessionID == nil, !immediate, !endIfIdle {
            for activeSessionID in activeSessionIDs {
                refresh(sessionID: activeSessionID)
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let targetSessionIDs = sessionID.map { [$0] } ?? Array(activeSessionIDs)
            for targetSessionID in targetSessionIDs {
                guard isActive(sessionID: targetSessionID),
                      let session = sessionSnapshot(for: targetSessionID) else { continue }
                let state = state(for: session)
                let status = viewModel.directoryStoreRegistry.snapshot(forSessionID: targetSessionID)?.status
                    ?? viewModel.sessionStatuses[targetSessionID]
                if endIfIdle && status == "idle" {
                    await LiveActivityCoordinator.end(sessionID: targetSessionID, state: state, immediate: false)
                    viewModel.activeLiveActivitySessionIDs.remove(targetSessionID)
                    viewModel.liveActivityStore.setLastState(nil, for: targetSessionID)
                    continue
                }
                if let previousState = viewModel.liveActivityStore.lastState(for: targetSessionID),
                   LiveActivitySnapshotBuilder.statesMatch(previousState, state) {
                    continue
                }
                await LiveActivityCoordinator.update(sessionID: targetSessionID, state: state)
                viewModel.liveActivityStore.setLastState(state, for: targetSessionID)
            }
        }
        #endif
    }

    func consumeReducerEvent(
        _ event: OpenCodeTypedEvent,
        result: SessionEventResult,
        sessionID: String?,
        eventType: String
    ) {
        if case let .sessionDeleted(session) = event, isActive(sessionID: session.id) {
            Task { [weak self] in await self?.stop(sessionID: session.id, immediate: true) }
            return
        }

        guard let sessionID, isActive(sessionID: sessionID) else { return }
        let interactionChanged: Bool
        switch result {
        case .permissionChanged, .questionChanged:
            interactionChanged = true
        default:
            interactionChanged = false
        }
        let messageChanged = EventSyncCoordinator.isLiveActivityMessageEventType(eventType)
        refresh(sessionID: sessionID, immediate: interactionChanged || messageChanged)

        if case .idle = result {
            scheduleCanonicalHydrationIfNeeded(sessionID: sessionID)
        }
    }

    func reducerDidCommit(sessionIDs: Set<String>) {
        for sessionID in sessionIDs where isActive(sessionID: sessionID) {
            refresh(sessionID: sessionID, immediate: true)
        }
    }

    func scheduleCanonicalHydrationIfNeeded(sessionID: String?) {
        guard viewModel.isConnected,
              viewModel.backendMode == .server,
              let sessionID,
              isActive(sessionID: sessionID),
              viewModel.selectedSession?.id != sessionID,
              let session = sessionSnapshot(for: sessionID) else { return }
        let targetGeneration = viewModel.directoryStoreRegistry.generation

        viewModel.liveActivityStore.setPreviewRefreshTask(Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            defer { viewModel.liveActivityStore.clearPreviewRefreshTask(for: sessionID) }
            do {
                let messages = try await viewModel.client.listMessages(sessionID: session.id, directory: session.directory)
                guard viewModel.directoryStoreRegistry.generation == targetGeneration else { return }
                let owner = viewModel.directoryStoreRegistry.ownerStore(forSessionID: session.id)
                    ?? viewModel.directoryStoreRegistry.store(for: session.directory)
                owner.applyCanonicalMessages(messages, forSessionID: session.id)
                viewModel.chatStore.cacheMessages(messages, forSessionID: session.id)
                viewModel.refreshSessionPreview(for: session.id, messages: messages)
                refresh(sessionID: session.id)
            } catch {
                return
            }
        }, for: sessionID)
    }

    #if canImport(ActivityKit) && os(iOS)
    func transcriptLines(for session: OpenCodeSession) -> [OpenCodeChatActivityLine] {
        LiveActivitySnapshotBuilder.transcriptLines(for: snapshotInput(for: session))
    }

    private func state(for session: OpenCodeSession) -> OpenCodeChatActivityAttributes.ContentState {
        LiveActivitySnapshotBuilder.state(for: snapshotInput(for: session))
    }

    private func snapshotInput(for session: OpenCodeSession) -> LiveActivitySnapshotInput {
        let canonical = viewModel.directoryStoreRegistry.snapshot(forSessionID: session.id)
        let isSelected = viewModel.selectedSession?.id == session.id
        let canonicalMessages = canonical?.messages ?? []
        return LiveActivitySnapshotInput(
            session: session,
            sessionTitle: sessionTitle(for: session),
            selectedSessionID: viewModel.selectedSession?.id,
            selectedMessages: isSelected ? viewModel.messages : canonicalMessages,
            cachedMessages: canonicalMessages.isEmpty
                ? (viewModel.cachedMessagesBySessionID[session.id] ?? [])
                : canonicalMessages,
            sessionStatus: canonical?.status ?? viewModel.sessionStatuses[session.id],
            sessionPreviewText: viewModel.sessionPreviews[session.id]?.text,
            permissions: isSelected ? viewModel.permissions(for: session.id) : (canonical?.permissions ?? []),
            questions: isSelected ? viewModel.questions(for: session.id) : (canonical?.questions ?? [])
        )
    }
    #endif

    private func sessionTitle(for session: OpenCodeSession) -> String {
        let title = viewModel.childSessionTitle(for: session).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Session" : title
    }

    private func sessionSnapshot(for sessionID: String) -> OpenCodeSession? {
        if let session = viewModel.directoryStoreRegistry.snapshot(forSessionID: sessionID)?.session
            ?? viewModel.session(matching: sessionID)
            ?? viewModel.sessions.first(where: { $0.id == sessionID })
            ?? (viewModel.selectedSession?.id == sessionID ? viewModel.selectedSession : nil) {
            return session
        }

        #if canImport(ActivityKit) && os(iOS)
        guard let activitySnapshot = LiveActivityCoordinator.sessionSnapshot(for: sessionID) else { return nil }
        return LiveActivityCoordinator.resolveSession(
            sessionID: sessionID,
            directory: nil,
            workspaceID: nil,
            knownSessions: [],
            selectedSession: nil,
            activitySnapshot: activitySnapshot
        ).session
        #else
        return nil
        #endif
    }
}
