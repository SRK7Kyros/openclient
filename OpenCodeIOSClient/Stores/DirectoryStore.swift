import Combine
import Foundation

@MainActor
final class DirectorySyncStore: ObservableObject {
    @Published private(set) var version: Int = 0
    var state: OpenCodeDirectorySyncState {
        didSet { version &+= 1 }
    }

    init(state: OpenCodeDirectorySyncState = OpenCodeDirectorySyncState()) {
        self.state = state
    }

    func messageCount(forSessionID sessionID: String) -> Int {
        state.messageCount(forSessionID: sessionID)
    }

    func messageEnvelopes(forSessionID sessionID: String, suffix count: Int) -> [OpenCodeMessageEnvelope] {
        state.messageEnvelopes(forSessionID: sessionID, suffix: count)
    }
}

@MainActor
final class DirectoryStore: ObservableObject {
    @Published var isLoadingSessions: Bool
    @Published var sessions: [OpenCodeSession]
    @Published var selectedSession: OpenCodeSession?
    @Published var commands: [OpenCodeCommand]
    @Published var sessionStatuses: [String: String]
    let syncStore: DirectorySyncStore

    var syncState: OpenCodeDirectorySyncState {
        get { syncStore.state }
        set { syncStore.state = newValue }
    }

    init(
        isLoadingSessions: Bool = false,
        sessions: [OpenCodeSession] = [],
        selectedSession: OpenCodeSession? = nil,
        commands: [OpenCodeCommand] = [],
        sessionStatuses: [String: String] = [:],
        syncState: OpenCodeDirectorySyncState = OpenCodeDirectorySyncState()
    ) {
        self.isLoadingSessions = isLoadingSessions
        self.sessions = sessions
        self.selectedSession = selectedSession
        self.commands = commands
        self.sessionStatuses = sessionStatuses
        self.syncStore = DirectorySyncStore(state: syncState)
    }

    func reset() {
        isLoadingSessions = false
        sessions = []
        selectedSession = nil
        commands = []
        sessionStatuses = [:]
        syncStore.state = OpenCodeDirectorySyncState()
    }

    @discardableResult
    func applyDirectoryReload(
        bootstrap: OpenCodeDirectoryBootstrap,
        statuses: [String: String],
        scopedSessions: [OpenCodeSession]
    ) -> Bool {
        var changed = false

        if isLoadingSessions {
            isLoadingSessions = false
            changed = true
        }
        if sessions != scopedSessions {
            sessions = scopedSessions
            changed = true
        }
        if commands != bootstrap.commands {
            commands = bootstrap.commands
            changed = true
        }
        if sessionStatuses != statuses {
            sessionStatuses = statuses
            changed = true
        }

        var nextSyncState = syncStore.state
        nextSyncState.permissionsBySessionID = Dictionary(grouping: bootstrap.permissions, by: \.sessionID)
        nextSyncState.questionsBySessionID = Dictionary(grouping: bootstrap.questions, by: \.sessionID)
        if nextSyncState != syncStore.state {
            syncStore.state = nextSyncState
            changed = true
        }

        return changed
    }

    @discardableResult
    func applySessionSelection(
        _ session: OpenCodeSession,
        cachedMessages: [OpenCodeMessageEnvelope]
    ) -> [OpenCodeMessageEnvelope] {
        let syncedMessages = syncStore.state.messageEnvelopes(forSessionID: session.id)
        let visibleMessages = syncedMessages.isEmpty ? cachedMessages : syncedMessages

        if syncedMessages.isEmpty, !cachedMessages.isEmpty {
            syncStore.state.replaceMessages(cachedMessages, forSessionID: session.id)
        }
        selectedSession = session

        return visibleMessages
    }

    func applyTodos(_ todos: [OpenCodeTodo], forSessionID sessionID: String) {
        syncStore.state.todosBySessionID[sessionID] = todos
    }

    func applySessionStatuses(_ statuses: [String: String]) {
        sessionStatuses = statuses
        syncStore.state.sessionStatusesBySessionID = statuses
    }

    func applyCanonicalMessages(_ messages: [OpenCodeMessageEnvelope], forSessionID sessionID: String) {
        syncStore.state.replaceMessages(messages, forSessionID: sessionID)
    }

    func appendMessage(_ message: OpenCodeMessageEnvelope, forSessionID sessionID: String) {
        syncStore.state.appendMessageEnvelope(message, forSessionID: sessionID)
    }

    @discardableResult
    func removeMessage(sessionID: String, messageID: String) -> Bool {
        syncStore.state.removeMessage(sessionID: sessionID, messageID: messageID)
    }

    func applyPermissions(_ permissions: [OpenCodePermission]) {
        syncStore.state.permissionsBySessionID = Dictionary(grouping: permissions, by: \.sessionID)
    }

    func clearPermissions() {
        syncStore.state.permissionsBySessionID = [:]
    }

    func applyQuestions(_ questions: [OpenCodeQuestionRequest]) {
        syncStore.state.questionsBySessionID = Dictionary(grouping: questions, by: \.sessionID)
    }

    func clearQuestions() {
        syncStore.state.questionsBySessionID = [:]
    }

    @discardableResult
    func applySelectedSessionAfterReload(_ nextSelectedSession: OpenCodeSession?) -> Bool {
        guard selectedSession != nextSelectedSession else { return false }
        selectedSession = nextSelectedSession
        return true
    }

    @discardableResult
    func applyReducedEventState(
        _ state: OpenCodeDirectoryEventState,
        scopedSessions: [OpenCodeSession]
    ) -> Bool {
        var changed = false

        if scopedSessions != sessions {
            sessions = scopedSessions
            changed = true
        }
        if state.selectedSession != selectedSession {
            selectedSession = state.selectedSession
            changed = true
        }
        if state.sessionStatuses != sessionStatuses {
            sessionStatuses = state.sessionStatuses
            changed = true
        }
        if state.syncState != syncStore.state {
            syncStore.state = state.syncState
            changed = true
        }

        return changed
    }
}
