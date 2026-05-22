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
            let sessionID = session.id
            let sessionTitle = liveActivitySessionTitle(for: session)
            let configSnapshot = config
            let sessionDirectory = session.directory
            let workspaceID = session.workspaceID

            try await Task.detached(priority: .userInitiated) {
                if let existing = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) {
                    await existing.update(LiveActivitySnapshotBuilder.content(state: state))
                    return
                }

                _ = try Activity.request(
                    attributes: OpenCodeChatActivityAttributes(
                        sessionID: sessionID,
                        sessionTitle: sessionTitle,
                        credentialID: configSnapshot.recentServerID,
                        serverBaseURL: configSnapshot.baseURL,
                        serverUsername: configSnapshot.username,
                        directory: sessionDirectory,
                        workspaceID: workspaceID
                    ),
                    content: LiveActivitySnapshotBuilder.content(state: state),
                    pushType: nil
                )
            }.value
            activeLiveActivitySessionIDs.insert(session.id)
            lastLiveActivityStatesBySessionID[session.id] = state
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
        let activities = Activity<OpenCodeChatActivityAttributes>.activities
        activeLiveActivitySessionIDs.formUnion(activities.map(\.attributes.sessionID))
        for activity in activities {
            lastLiveActivityStatesBySessionID[activity.attributes.sessionID] = activity.content.state
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

        liveActivityPreviewRefreshTasksBySessionID[sessionID]?.cancel()
        liveActivityPreviewRefreshTasksBySessionID[sessionID] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            do {
                let messages = try await self.client.listMessages(sessionID: session.id, directory: session.directory)
                self.chatStore.cacheMessages(messages, forSessionID: session.id)
                self.refreshSessionPreview(for: session.id, messages: messages)
                self.refreshLiveActivityIfNeeded(for: session.id)
            } catch {
                return
            }

            self.liveActivityPreviewRefreshTasksBySessionID[sessionID] = nil
        }
    }

    func stopLiveActivity(for session: OpenCodeSession, immediate: Bool = false) async {
        await stopLiveActivity(for: session.id, immediate: immediate)
    }

    func stopLiveActivity(for sessionID: String, immediate: Bool = false) async {
        #if canImport(ActivityKit) && os(iOS)
        liveActivityRefreshTasksBySessionID[sessionID]?.cancel()
        liveActivityRefreshTasksBySessionID[sessionID] = nil
        let session = liveActivitySessionSnapshot(for: sessionID)
        let finalState = session.map { liveActivityState(for: $0) }
        let gracePeriod = immediate ? nil : LiveActivitySnapshotBuilder.gracePeriod
        await Task.detached(priority: .userInitiated) {
            guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) else { return }
            let dismissalPolicy: ActivityUIDismissalPolicy = {
                guard let gracePeriod else { return .immediate }
                return .after(Date().addingTimeInterval(gracePeriod))
            }()
            await activity.end(LiveActivitySnapshotBuilder.content(state: finalState ?? activity.content.state), dismissalPolicy: dismissalPolicy)
        }.value
        activeLiveActivitySessionIDs.remove(sessionID)
        lastLiveActivityStatesBySessionID[sessionID] = nil
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
                pendingRefreshExists: liveActivityRefreshTasksBySessionID[sessionID] != nil,
                immediate: immediate,
                endIfIdle: endIfIdle
            ) else {
                return
            }
            liveActivityRefreshTasksBySessionID[sessionID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.liveActivityRefreshDelay)
                guard !Task.isCancelled else { return }
                self?.refreshLiveActivityIfNeeded(for: sessionID, endIfIdle: endIfIdle, immediate: true)
                self?.liveActivityRefreshTasksBySessionID[sessionID] = nil
            }
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
                    await Task.detached(priority: .utility) {
                        guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == targetSessionID }) else { return }
                        await activity.end(
                            LiveActivitySnapshotBuilder.content(state: state),
                            dismissalPolicy: .after(Date().addingTimeInterval(LiveActivitySnapshotBuilder.gracePeriod))
                        )
                    }.value
                    self.activeLiveActivitySessionIDs.remove(targetSessionID)
                    self.lastLiveActivityStatesBySessionID[targetSessionID] = nil
                    continue
                }

                if let previousState = self.lastLiveActivityStatesBySessionID[targetSessionID],
                   LiveActivitySnapshotBuilder.statesMatch(previousState, state) {
                    continue
                }

                await Task.detached(priority: .utility) {
                    guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == targetSessionID }) else { return }
                    await activity.update(LiveActivitySnapshotBuilder.content(state: state))
                }.value
                self.lastLiveActivityStatesBySessionID[targetSessionID] = state
            }
        }
        #endif
    }

    func handleLiveActivityURL(_ url: URL) async {
        guard url.scheme == OpenCodeChatActivityDeepLink.scheme,
              url.host == OpenCodeChatActivityDeepLink.host else {
            return
        }

        if !isConnected {
            guard hasSavedServer else { return }
            await connect()
            guard isConnected else { return }
        }

        let pathComponents = url.pathComponents
        guard pathComponents.count >= 3, pathComponents[1] == "session" else { return }

        let sessionID = pathComponents[2]
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let action = queryItems.first(where: { $0.name == "action" })?.value
        let directory = queryItems.first(where: { $0.name == "directory" })?.value
        let workspaceID = queryItems.first(where: { $0.name == "workspace" })?.value

        if !isUsingAppleIntelligence, effectiveSelectedDirectory != directory {
            await selectDirectory(directory)
        }

        await openLiveActivitySession(sessionID: sessionID, directory: directory, workspaceID: workspaceID)

        switch action {
        case "permission":
            guard let requestID = queryItems.first(where: { $0.name == "requestID" })?.value,
                  let reply = queryItems.first(where: { $0.name == "reply" })?.value,
                  let permission = permissions(for: sessionID).first(where: { $0.id == requestID }) else {
                return
            }
            await respondToPermission(permission, response: reply)
            refreshLiveActivityIfNeeded(for: sessionID)
        case "question":
            guard let requestID = queryItems.first(where: { $0.name == "requestID" })?.value,
                  let answer = queryItems.first(where: { $0.name == "answer" })?.value,
                  let question = questions(for: sessionID).first(where: { $0.id == requestID }) else {
                return
            }
            await respondToQuestion(question, answers: [[answer]])
            refreshLiveActivityIfNeeded(for: sessionID)
        default:
            return
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
        guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) else {
            return nil
        }

        return OpenCodeSession(
            id: activity.attributes.sessionID,
            title: activity.attributes.sessionTitle,
            workspaceID: activity.attributes.workspaceID,
            directory: activity.attributes.directory,
            projectID: nil,
            parentID: nil
        )
        #else
        return nil
        #endif
    }

    private func openLiveActivitySession(sessionID: String, directory: String?, workspaceID: String?) async {
        if session(matching: sessionID) == nil {
            await ensureAllSessionsLoaded()
        }

        if let session = session(matching: sessionID) {
            await selectSession(session)
            return
        }

        let fallback = liveActivityFallbackSession(sessionID: sessionID, directory: directory, workspaceID: workspaceID)
        upsertVisibleSession(fallback)
        await selectSession(fallback)
    }

    private func liveActivityFallbackSession(sessionID: String, directory: String?, workspaceID: String?) -> OpenCodeSession {
        #if canImport(ActivityKit) && os(iOS)
        if let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) {
            return OpenCodeSession(
                id: activity.attributes.sessionID,
                title: activity.attributes.sessionTitle,
                workspaceID: activity.attributes.workspaceID,
                directory: activity.attributes.directory,
                projectID: nil,
                parentID: nil
            )
        }
        #endif

        return OpenCodeSession(
            id: sessionID,
            title: "Session",
            workspaceID: workspaceID,
            directory: directory,
            projectID: nil,
            parentID: nil
        )
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
