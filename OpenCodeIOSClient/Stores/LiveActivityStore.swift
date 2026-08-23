import Combine
import Foundation

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

@MainActor
final class LiveActivityStore: ObservableObject {
    @Published var activeSessionIDs: Set<String>
    var previewRefreshTasksBySessionID: [String: Task<Void, Never>]
    var refreshTasksBySessionID: [String: Task<Void, Never>]
#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
    var lastStatesBySessionID: [String: OpenCodeChatActivityAttributes.ContentState]
#endif

    init(
        activeSessionIDs: Set<String> = [],
        previewRefreshTasksBySessionID: [String: Task<Void, Never>] = [:],
        refreshTasksBySessionID: [String: Task<Void, Never>] = [:]
    ) {
        self.activeSessionIDs = activeSessionIDs
        self.previewRefreshTasksBySessionID = previewRefreshTasksBySessionID
        self.refreshTasksBySessionID = refreshTasksBySessionID
#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
        self.lastStatesBySessionID = [:]
#endif
    }

    func insertActiveSessionID(_ sessionID: String) {
        activeSessionIDs.insert(sessionID)
    }

    func removeActiveSessionID(_ sessionID: String) {
        activeSessionIDs.remove(sessionID)
    }

    func cancelPreviewRefresh(for sessionID: String) {
        previewRefreshTasksBySessionID[sessionID]?.cancel()
        previewRefreshTasksBySessionID[sessionID] = nil
    }

    func setPreviewRefreshTask(_ task: Task<Void, Never>?, for sessionID: String) {
        previewRefreshTasksBySessionID[sessionID]?.cancel()
        previewRefreshTasksBySessionID[sessionID] = task
    }

    func clearPreviewRefreshTask(for sessionID: String) {
        previewRefreshTasksBySessionID[sessionID] = nil
    }

    func cancelRefresh(for sessionID: String) {
        refreshTasksBySessionID[sessionID]?.cancel()
        refreshTasksBySessionID[sessionID] = nil
    }

    func setRefreshTask(_ task: Task<Void, Never>?, for sessionID: String) {
        refreshTasksBySessionID[sessionID]?.cancel()
        refreshTasksBySessionID[sessionID] = task
    }

    func clearRefreshTask(for sessionID: String) {
        refreshTasksBySessionID[sessionID] = nil
    }

    func hasPendingRefresh(for sessionID: String) -> Bool {
        refreshTasksBySessionID[sessionID] != nil
    }

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
    func setLastState(_ state: OpenCodeChatActivityAttributes.ContentState?, for sessionID: String) {
        lastStatesBySessionID[sessionID] = state
    }

    func lastState(for sessionID: String) -> OpenCodeChatActivityAttributes.ContentState? {
        lastStatesBySessionID[sessionID]
    }
#endif
}
