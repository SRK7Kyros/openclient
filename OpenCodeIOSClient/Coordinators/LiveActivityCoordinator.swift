import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct LiveActivityStartRequest {
    var sessionID: String
    var sessionTitle: String
    var credentialID: String
    var serverBaseURL: String
    var serverUsername: String
    var directory: String?
    var workspaceID: String?
    var state: OpenCodeChatActivityAttributes.ContentState
}

struct LiveActivitySessionSnapshot {
    var sessionID: String
    var sessionTitle: String
    var workspaceID: String?
    var directory: String?
}

enum LiveActivityCoordinator {
    static func requestOrUpdate(_ request: LiveActivityStartRequest) async throws {
        try await Task.detached(priority: .userInitiated) {
            if let existing = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == request.sessionID }) {
                await existing.update(LiveActivitySnapshotBuilder.content(state: request.state))
                return
            }

            _ = try Activity.request(
                attributes: OpenCodeChatActivityAttributes(
                    sessionID: request.sessionID,
                    sessionTitle: request.sessionTitle,
                    credentialID: request.credentialID,
                    serverBaseURL: request.serverBaseURL,
                    serverUsername: request.serverUsername,
                    directory: request.directory,
                    workspaceID: request.workspaceID
                ),
                content: LiveActivitySnapshotBuilder.content(state: request.state),
                pushType: nil
            )
        }.value
    }

    static func update(sessionID: String, state: OpenCodeChatActivityAttributes.ContentState) async {
        await Task.detached(priority: .utility) {
            guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) else { return }
            await activity.update(LiveActivitySnapshotBuilder.content(state: state))
        }.value
    }

    static func end(sessionID: String, state: OpenCodeChatActivityAttributes.ContentState, immediate: Bool) async {
        await Task.detached(priority: .userInitiated) {
            guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) else { return }
            let dismissalPolicy: ActivityUIDismissalPolicy = immediate
                ? .immediate
                : .after(Date().addingTimeInterval(LiveActivitySnapshotBuilder.gracePeriod))
            await activity.end(LiveActivitySnapshotBuilder.content(state: state), dismissalPolicy: dismissalPolicy)
        }.value
    }

    static func activeSessionIDs() -> Set<String> {
        Set(Activity<OpenCodeChatActivityAttributes>.activities.map(\.attributes.sessionID))
    }

    static func currentStatesBySessionID() -> [String: OpenCodeChatActivityAttributes.ContentState] {
        Dictionary(uniqueKeysWithValues: Activity<OpenCodeChatActivityAttributes>.activities.map { ($0.attributes.sessionID, $0.content.state) })
    }

    static func sessionSnapshot(for sessionID: String) -> LiveActivitySessionSnapshot? {
        guard let activity = Activity<OpenCodeChatActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) else { return nil }
        return LiveActivitySessionSnapshot(
            sessionID: activity.attributes.sessionID,
            sessionTitle: activity.attributes.sessionTitle,
            workspaceID: activity.attributes.workspaceID,
            directory: activity.attributes.directory
        )
    }
}
#endif
