import Foundation
import SwiftUI

extension AppViewModel {
    func toggleLiveActivity(for session: OpenCodeSession) async {
        await liveActivityFacade.toggle(session: session)
    }

    func startLiveActivity(for session: OpenCodeSession, userVisibleErrors: Bool = true) async {
        await liveActivityFacade.start(session: session, userVisibleErrors: userVisibleErrors)
    }

    func maybeAutoStartLiveActivity(for session: OpenCodeSession) async {
        await liveActivityFacade.autoStartIfEnabled(session: session)
    }

    func reconcileLiveActivities() {
        liveActivityFacade.reconcile()
    }

    func scheduleLiveActivityPreviewRefreshIfNeeded(for sessionID: String?) {
        liveActivityFacade.scheduleCanonicalHydrationIfNeeded(sessionID: sessionID)
    }

    func stopLiveActivity(for session: OpenCodeSession, immediate: Bool = false) async {
        await liveActivityFacade.stop(sessionID: session.id, immediate: immediate)
    }

    func stopLiveActivity(for sessionID: String, immediate: Bool = false) async {
        await liveActivityFacade.stop(sessionID: sessionID, immediate: immediate)
    }

    nonisolated static func shouldScheduleLiveActivityRefresh(
        pendingRefreshExists: Bool,
        immediate: Bool,
        endIfIdle: Bool
    ) -> Bool {
        !pendingRefreshExists && !immediate && !endIfIdle
    }

    func refreshLiveActivityIfNeeded(
        for sessionID: String? = nil,
        endIfIdle: Bool = false,
        immediate: Bool = false
    ) {
        liveActivityFacade.refresh(sessionID: sessionID, endIfIdle: endIfIdle, immediate: immediate)
    }

    func handleLiveActivityURL(_ url: URL) async {
        guard let deepLink = LiveActivityCoordinator.deepLink(from: url) else { return }
        openURLNavigationMessage = "Opening chat..."
        defer { openURLNavigationMessage = nil }
        appendDebugLog("live activity deep link session=\(deepLink.sessionID) dir=\(debugDirectoryLabel(deepLink.directory)) action=\(deepLink.action)")

        if !isConnected {
            guard hasSavedServer else { return }
            await connect()
            guard isConnected else { return }
        }

        await openLiveActivitySession(deepLink)

        switch deepLink.action {
        case .open:
            return
        case let .permission(requestID, reply):
            guard let permission = permissions(for: deepLink.sessionID).first(where: { $0.id == requestID }) else { return }
            await respondToPermission(permission, response: reply)
            liveActivityFacade.refresh(sessionID: deepLink.sessionID)
        case let .question(requestID, answer):
            guard let question = questions(for: deepLink.sessionID).first(where: { $0.id == requestID }) else { return }
            await respondToQuestion(question, answers: [[answer]])
            liveActivityFacade.refresh(sessionID: deepLink.sessionID)
        }
    }

    func isLiveActivityActive(for session: OpenCodeSession) -> Bool {
        liveActivityFacade.isActive(sessionID: session.id)
    }

    #if canImport(ActivityKit) && os(iOS)
    func liveActivityTranscriptLines(for session: OpenCodeSession) -> [OpenCodeChatActivityLine] {
        liveActivityFacade.transcriptLines(for: session)
    }
    #endif

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
        let resolvedDirectory = openedSession.directory ?? deepLink.directory
        let shouldSwitchDirectory = !isUsingAppleIntelligence && (currentProject == nil || effectiveSelectedDirectory != resolvedDirectory)
        let routeProject = resolvedDirectory.flatMap(projectContainingDirectory)
        if let routeProject {
            withAnimation(opencodeSelectionAnimation) {
                currentProject = routeProject
                selectedProjectContentTab = .sessions
            }
        }

        if shouldSwitchDirectory {
            await selectDirectory(resolvedDirectory)
            if let routeProject {
                withAnimation(opencodeSelectionAnimation) {
                    currentProject = routeProject
                    selectedProjectContentTab = .sessions
                }
            }
        }

        if case .fallback = resolution {
            upsertVisibleSession(openedSession)
        }
        await selectSession(openedSession)
        chatDetailPresentationRequest &+= 1
        return openedSession
    }

    private func projectContainingDirectory(_ directory: String) -> OpenCodeProject? {
        let key = workspaceKey(directory)
        return projects.first { project in
            guard project.id != "global" else { return false }
            if workspaceKey(project.worktree) == key { return true }
            return project.sandboxes?.contains { workspaceKey($0) == key } == true
        }
    }
}
