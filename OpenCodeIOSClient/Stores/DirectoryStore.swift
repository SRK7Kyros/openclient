import Combine
import Foundation

struct DirectorySessionSnapshot {
    let session: OpenCodeSession?
    let status: String?
    let messages: [OpenCodeMessageEnvelope]
    let todos: [OpenCodeTodo]
    let permissions: [OpenCodePermission]
    let questions: [OpenCodeQuestionRequest]
}

@MainActor
final class DirectoryStoreRegistry: ObservableObject {
    static let globalKey = "global"

    @Published private(set) var activeStore: DirectoryStore
    @Published private(set) var activeKey: String
    @Published private(set) var generation: Int
    private var storesByKey: [String: DirectoryStore]

    init(activeDirectory: String? = nil) {
        let key = Self.key(for: activeDirectory)
        let store = DirectoryStore()
        activeKey = key
        activeStore = store
        generation = 0
        storesByKey = [key: store]
    }

    static func key(for directory: String?) -> String {
        guard var directory, !directory.isEmpty, directory != globalKey else {
            return globalKey
        }
        directory = directory.replacingOccurrences(of: "\\", with: "/")
        while directory.count > 1, directory.hasSuffix("/") {
            directory.removeLast()
        }
        return directory
    }

    static func directory(forKey key: String) -> String? {
        key == globalKey ? nil : key
    }

    @discardableResult
    func activate(_ directory: String?) -> DirectoryStore {
        let key = Self.key(for: directory)
        let store = self.store(for: directory)
        guard key != activeKey || store !== activeStore else { return store }
        activeKey = key
        activeStore = store
        return store
    }

    func store(for directory: String?) -> DirectoryStore {
        let key = Self.key(for: directory)
        if let store = storesByKey[key] {
            return store
        }
        let store = DirectoryStore()
        storesByKey[key] = store
        return store
    }

    func existingStore(for directory: String?) -> DirectoryStore? {
        storesByKey[Self.key(for: directory)]
    }

    func key(for store: DirectoryStore) -> String? {
        storesByKey.first { $0.value === store }?.key
    }

    func contains(_ store: DirectoryStore, forKey key: String) -> Bool {
        storesByKey[key] === store
    }

    func stores(containingSessionID sessionID: String) -> [DirectoryStore] {
        storesByKey.values.filter { store in
            store.sessions.contains { $0.id == sessionID }
                || store.syncState.messagesBySessionID[sessionID] != nil
                || store.syncState.todosBySessionID[sessionID] != nil
                || store.syncState.permissionsBySessionID[sessionID] != nil
                || store.syncState.questionsBySessionID[sessionID] != nil
        }
    }

    func stores(containingMessageID messageID: String) -> [DirectoryStore] {
        storesByKey.values.filter { store in
            store.syncState.messagesBySessionID.values.contains { messages in
                messages.contains { $0.id == messageID }
            }
        }
    }

    func ownerStore(forSessionID sessionID: String) -> DirectoryStore? {
        if activeStore.sessions.contains(where: { $0.id == sessionID })
            || activeStore.selectedSession?.id == sessionID
            || activeStore.syncState.messagesBySessionID[sessionID] != nil {
            return activeStore
        }
        return stores(containingSessionID: sessionID).first
    }

    func session(matching sessionID: String) -> OpenCodeSession? {
        for store in storesByKey.values {
            if let session = store.sessions.first(where: { $0.id == sessionID }) {
                return session
            }
        }
        return nil
    }

    func snapshot(forSessionID sessionID: String) -> DirectorySessionSnapshot? {
        guard let store = ownerStore(forSessionID: sessionID) else { return nil }
        return DirectorySessionSnapshot(
            session: store.sessions.first(where: { $0.id == sessionID })
                ?? (store.selectedSession?.id == sessionID ? store.selectedSession : nil),
            status: store.sessionStatuses[sessionID] ?? store.syncState.sessionStatusesBySessionID[sessionID],
            messages: store.syncState.messageEnvelopes(forSessionID: sessionID),
            todos: store.syncState.todosBySessionID[sessionID] ?? [],
            permissions: store.syncState.permissionsBySessionID[sessionID] ?? [],
            questions: store.syncState.questionsBySessionID[sessionID] ?? []
        )
    }

    func reset() {
        let store = DirectoryStore()
        storesByKey = [Self.globalKey: store]
        activeKey = Self.globalKey
        activeStore = store
        generation &+= 1
    }
}

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

    func userMessageCount(forSessionID sessionID: String) -> Int {
        state.userMessageCount(forSessionID: sessionID)
    }

    func messageCountIncludingLatestUserRounds(
        _ roundCount: Int,
        fallbackMessageCount: Int,
        forSessionID sessionID: String
    ) -> Int {
        state.messageCountIncludingLatestUserRounds(
            roundCount,
            fallbackMessageCount: fallbackMessageCount,
            forSessionID: sessionID
        )
    }

    func containsMessage(id messageID: String, forSessionID sessionID: String) -> Bool {
        state.messagesBySessionID[sessionID]?.contains { $0.id == messageID } == true
    }
}

@MainActor
final class DirectoryStore: ObservableObject {
    private static let immediateTranscriptRoundLimit = 3
    private static let immediateTranscriptFallbackLimit = 3

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
        nextSyncState.sessionStatusesBySessionID = statuses
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
        let syncedMessageCount = syncStore.messageCount(forSessionID: session.id)
        let syncedVisibleMessageCount = syncStore.messageCountIncludingLatestUserRounds(
            Self.immediateTranscriptRoundLimit,
            fallbackMessageCount: Self.immediateTranscriptFallbackLimit,
            forSessionID: session.id
        )
        let syncedMessages = syncStore.messageEnvelopes(
            forSessionID: session.id,
            suffix: syncedVisibleMessageCount
        )
        let cachedTail = Self.immediateTranscript(in: cachedMessages)
        let visibleMessages = syncedMessages.isEmpty ? cachedTail : syncedMessages

        if syncedMessageCount == 0, !cachedTail.isEmpty {
            syncStore.state.replaceMessages(cachedTail, forSessionID: session.id)
        }
        selectedSession = session

        return visibleMessages
    }

    private static func immediateTranscript(
        in messages: [OpenCodeMessageEnvelope]
    ) -> [OpenCodeMessageEnvelope] {
        guard !messages.isEmpty else { return [] }
        var remainingRounds = immediateTranscriptRoundLimit
        var oldestUserIndex: Int?
        for index in messages.indices.reversed() where (messages[index].info.role ?? "").lowercased() == "user" {
            oldestUserIndex = index
            remainingRounds -= 1
            if remainingRounds == 0 {
                return Array(messages[index...])
            }
        }
        if let oldestUserIndex {
            return Array(messages[oldestUserIndex...])
        }
        return Array(messages.suffix(immediateTranscriptFallbackLimit))
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
