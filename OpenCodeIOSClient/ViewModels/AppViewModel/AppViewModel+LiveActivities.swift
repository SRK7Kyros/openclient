import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

extension AppViewModel {
    private static let liveActivityRefreshDelay: Duration = .milliseconds(350)

    func toggleLiveActivity(for session: OpenCodeSession) async {
        if activeLiveActivitySessionIDs.contains(session.id) {
            await stopLiveActivity(for: session.id, immediate: true)
        } else {
            await startLiveActivity(for: session)
        }
    }

    func startLiveActivity(for session: OpenCodeSession, userVisibleErrors: Bool = true) async {
        #if canImport(ActivityKit) && os(iOS)
        do {
            let state = liveActivityState(for: session)
            let configSnapshot = config
            try await LiveActivityCoordinator.requestOrUpdate(
                LiveActivityStartRequest(
                    sessionID: session.id,
                    sessionTitle: liveActivitySessionTitle(for: session),
                    credentialID: configSnapshot.recentServerID,
                    serverBaseURL: configSnapshot.baseURL,
                    serverUsername: configSnapshot.username,
                    directory: session.isGlobalScopeSession ? nil : session.directory,
                    workspaceID: session.workspaceID,
                    state: state
                )
            )
            activeLiveActivitySessionIDs.insert(session.id)
            liveActivityStore.setLastState(state, for: session.id)
            if userVisibleErrors {
                errorMessage = nil
            }
        } catch {
            if userVisibleErrors {
                errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    func maybeAutoStartLiveActivity(for session: OpenCodeSession) async {
        guard !isUsingAppleIntelligence, isLiveActivityAutoStartEnabled else { return }
        guard !activeLiveActivitySessionIDs.contains(session.id) else { return }
        await startLiveActivity(for: session, userVisibleErrors: false)
    }

    func reconcileLiveActivities() {
        #if canImport(ActivityKit) && os(iOS)
        activeLiveActivitySessionIDs.formUnion(LiveActivityCoordinator.activeSessionIDs())
        for (sessionID, state) in LiveActivityCoordinator.currentStatesBySessionID() {
            liveActivityStore.setLastState(state, for: sessionID)
        }
        #endif
    }

    func scheduleLiveActivityPreviewRefreshIfNeeded(for sessionID: String?) {
        guard let sessionID,
              activeLiveActivitySessionIDs.contains(sessionID),
              selectedSession?.id != sessionID,
              let session = liveActivitySessionSnapshot(for: sessionID) else {
            return
        }

        liveActivityStore.setPreviewRefreshTask(Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            do {
                let messages = try await self.client.listMessages(sessionID: session.id, directory: session.directory)
                self.chatStore.cacheMessages(messages, forSessionID: session.id)
                self.refreshSessionPreview(for: session.id, messages: messages)
                self.refreshLiveActivityIfNeeded(for: session.id)
            } catch {
                self.liveActivityStore.clearPreviewRefreshTask(for: sessionID)
                return
            }

            self.liveActivityStore.clearPreviewRefreshTask(for: sessionID)
        }, for: sessionID)
    }

    func stopLiveActivity(for session: OpenCodeSession, immediate: Bool = false) async {
        await stopLiveActivity(for: session.id, immediate: immediate)
    }

    func stopLiveActivity(for sessionID: String, immediate: Bool = false) async {
        #if canImport(ActivityKit) && os(iOS)
        liveActivityStore.cancelRefresh(for: sessionID)
        let session = liveActivitySessionSnapshot(for: sessionID)
        if let finalState = session.map({ liveActivityState(for: $0) }) ?? liveActivityStore.lastState(for: sessionID) {
            await LiveActivityCoordinator.end(sessionID: sessionID, state: finalState, immediate: immediate)
        }
        activeLiveActivitySessionIDs.remove(sessionID)
        liveActivityStore.setLastState(nil, for: sessionID)
        #endif
    }

    nonisolated static func shouldScheduleLiveActivityRefresh(pendingRefreshExists: Bool, immediate: Bool, endIfIdle: Bool) -> Bool {
        LiveActivitySnapshotBuilder.shouldScheduleRefresh(pendingRefreshExists: pendingRefreshExists, immediate: immediate, endIfIdle: endIfIdle)
    }

    func refreshLiveActivityIfNeeded(for sessionID: String? = nil, endIfIdle: Bool = false, immediate: Bool = false) {
        #if canImport(ActivityKit) && os(iOS)
        if let sessionID, !immediate, !endIfIdle {
            guard activeLiveActivitySessionIDs.contains(sessionID) else { return }
            guard Self.shouldScheduleLiveActivityRefresh(
                pendingRefreshExists: liveActivityStore.hasPendingRefresh(for: sessionID),
                immediate: immediate,
                endIfIdle: endIfIdle
            ) else {
                return
            }
            liveActivityStore.setRefreshTask(Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.liveActivityRefreshDelay)
                guard !Task.isCancelled else { return }
                self?.refreshLiveActivityIfNeeded(for: sessionID, endIfIdle: endIfIdle, immediate: true)
                self?.liveActivityStore.clearRefreshTask(for: sessionID)
            }, for: sessionID)
            return
        }

        if sessionID == nil, !immediate, !endIfIdle {
            for activeSessionID in activeLiveActivitySessionIDs {
                refreshLiveActivityIfNeeded(for: activeSessionID)
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let targetSessionIDs: [String]
            if let sessionID {
                guard self.activeLiveActivitySessionIDs.contains(sessionID) else { return }
                targetSessionIDs = [sessionID]
            } else {
                targetSessionIDs = Array(self.activeLiveActivitySessionIDs)
            }

            for targetSessionID in targetSessionIDs {
                guard let session = self.liveActivitySessionSnapshot(for: targetSessionID) else {
                    continue
                }

                let state = self.liveActivityState(for: session)
                if endIfIdle && self.sessionStatuses[targetSessionID] == "idle" {
                    await LiveActivityCoordinator.end(sessionID: targetSessionID, state: state, immediate: false)
                    self.activeLiveActivitySessionIDs.remove(targetSessionID)
                    self.liveActivityStore.setLastState(nil, for: targetSessionID)
                    continue
                }

                if let previousState = self.liveActivityStore.lastState(for: targetSessionID),
                   LiveActivitySnapshotBuilder.statesMatch(previousState, state) {
                    continue
                }

                await LiveActivityCoordinator.update(sessionID: targetSessionID, state: state)
                self.liveActivityStore.setLastState(state, for: targetSessionID)
            }
        }
        #endif
    }

    func handleLiveActivityURL(_ url: URL) async {
        guard let deepLink = LiveActivityCoordinator.deepLink(from: url) else { return }

        if !isConnected {
            guard hasSavedServer else { return }
            await connect()
            guard isConnected else { return }
        }

        let openedSession = await openLiveActivitySession(deepLink)
        let resolvedDirectory = openedSession?.directory ?? deepLink.directory
        if !isUsingAppleIntelligence, currentProject == nil || effectiveSelectedDirectory != resolvedDirectory {
            await selectDirectory(resolvedDirectory)
            if let openedSession {
                await selectSession(openedSession)
            }
        }

        switch deepLink.action {
        case .open:
            return
        case let .permission(requestID, reply):
            guard let permission = permissions(for: deepLink.sessionID).first(where: { $0.id == requestID }) else {
                return
            }
            await respondToPermission(permission, response: reply)
            refreshLiveActivityIfNeeded(for: deepLink.sessionID)
        case let .question(requestID, answer):
            guard let question = questions(for: deepLink.sessionID).first(where: { $0.id == requestID }) else {
                return
            }
            await respondToQuestion(question, answers: [[answer]])
            refreshLiveActivityIfNeeded(for: deepLink.sessionID)
        }
    }

    func isLiveActivityActive(for session: OpenCodeSession) -> Bool {
        activeLiveActivitySessionIDs.contains(session.id)
    }

    private func liveActivitySessionSnapshot(for sessionID: String) -> OpenCodeSession? {
        if let session = session(matching: sessionID) ?? sessions.first(where: { $0.id == sessionID }) ?? (selectedSession?.id == sessionID ? selectedSession : nil) {
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

    @discardableResult
    private func openLiveActivitySession(_ deepLink: LiveActivityDeepLink) async -> OpenCodeSession? {
        if session(matching: deepLink.sessionID) == nil {
            await ensureAllSessionsLoaded()
        }

        #if canImport(ActivityKit) && os(iOS)
        let activitySnapshot = LiveActivityCoordinator.sessionSnapshot(for: deepLink.sessionID)
        #else
        let activitySnapshot: LiveActivitySessionSnapshot? = nil
        #endif

        let resolution = LiveActivityCoordinator.resolveSession(
            sessionID: deepLink.sessionID,
            directory: deepLink.directory,
            workspaceID: deepLink.workspaceID,
            knownSessions: allSessions,
            selectedSession: selectedSession,
            activitySnapshot: activitySnapshot
        )
        let openedSession = resolution.session
        if case .fallback = resolution {
            upsertVisibleSession(openedSession)
        }
        await selectSession(openedSession)
        return openedSession
    }

    #if canImport(ActivityKit) && os(iOS)
    private func liveActivityState(for session: OpenCodeSession) -> OpenCodeChatActivityAttributes.ContentState {
        LiveActivitySnapshotBuilder.state(for: liveActivitySnapshotInput(for: session))
    }

    private func liveActivitySessionTitle(for session: OpenCodeSession) -> String {
        let title = childSessionTitle(for: session)
        return LiveActivitySnapshotBuilder.sessionTitle(title)
    }

    func liveActivityTranscriptLines(for session: OpenCodeSession) -> [OpenCodeChatActivityLine] {
        LiveActivitySnapshotBuilder.transcriptLines(for: liveActivitySnapshotInput(for: session))
    }

    private func liveActivitySnapshotInput(for session: OpenCodeSession) -> LiveActivitySnapshotInput {
        LiveActivitySnapshotInput(
            session: session,
            sessionTitle: liveActivitySessionTitle(for: session),
            selectedSessionID: selectedSession?.id,
            selectedMessages: messages,
            cachedMessages: cachedMessagesBySessionID[session.id] ?? [],
            sessionStatus: sessionStatuses[session.id],
            sessionPreviewText: sessionPreviews[session.id]?.text,
            permissions: permissions(for: session.id),
            questions: questions(for: session.id)
        )
    }
    #endif
}
