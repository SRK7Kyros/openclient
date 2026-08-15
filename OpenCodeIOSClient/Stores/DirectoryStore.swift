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

    func latestUserMessageEnvelope(
        beforeSuffixCount suffixCount: Int,
        forSessionID sessionID: String
    ) -> OpenCodeMessageEnvelope? {
        state.latestUserMessageEnvelope(
            beforeSuffixCount: suffixCount,
            forSessionID: sessionID
        )
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
    private static let immediateTranscriptRoundLimit = 1
    private static let immediateTranscriptMessageLimit = 12

    @Published var isLoadingSessions: Bool
    @Published var sessions: [OpenCodeSession]
    @Published var sessionTotal: Int
    @Published var sessionLimit: Int
    @Published var selectedSession: OpenCodeSession?
    @Published var commands: [OpenCodeCommand]
    @Published var sessionStatuses: [String: String]
    let syncStore: DirectorySyncStore
    private(set) var permissionRevision: UInt = 0
    private(set) var questionRevision: UInt = 0

    var syncState: OpenCodeDirectorySyncState {
        get { syncStore.state }
        set { syncStore.state = newValue }
    }

    init(
        isLoadingSessions: Bool = false,
        sessions: [OpenCodeSession] = [],
        sessionTotal: Int = 0,
        sessionLimit: Int = 100,
        selectedSession: OpenCodeSession? = nil,
        commands: [OpenCodeCommand] = [],
        sessionStatuses: [String: String] = [:],
        syncState: OpenCodeDirectorySyncState = OpenCodeDirectorySyncState()
    ) {
        self.isLoadingSessions = isLoadingSessions
        self.sessions = sessions
        self.sessionTotal = sessionTotal
        self.sessionLimit = sessionLimit
        self.selectedSession = selectedSession
        self.commands = commands
        self.sessionStatuses = sessionStatuses
        self.syncStore = DirectorySyncStore(state: syncState)
    }

    func reset() {
        isLoadingSessions = false
        sessions = []
        sessionTotal = 0
        sessionLimit = 100
        selectedSession = nil
        commands = []
        sessionStatuses = [:]
        syncStore.state = OpenCodeDirectorySyncState()
        permissionRevision = 0
        questionRevision = 0
    }

    @discardableResult
    func applyDirectoryReload(
        bootstrap: OpenCodeDirectoryBootstrap,
        statuses: [String: String],
        scopedSessions: [OpenCodeSession],
        permissionRevisionAtRequestStart: UInt? = nil,
        questionRevisionAtRequestStart: UInt? = nil
    ) -> Bool {
        var changed = false
        let knownChildren = sessions.filter { !$0.isRootSession && !$0.isArchived }
        let reconciledSessions = Self.deduplicatedSessions(scopedSessions + knownChildren)

        if isLoadingSessions {
            isLoadingSessions = false
            changed = true
        }
        if sessions != reconciledSessions {
            sessions = reconciledSessions
            changed = true
        }
        if sessionTotal != bootstrap.sessionTotal {
            sessionTotal = bootstrap.sessionTotal
            changed = true
        }
        if sessionLimit != bootstrap.sessionLimit {
            sessionLimit = bootstrap.sessionLimit
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
        if permissionRevisionAtRequestStart == nil || permissionRevisionAtRequestStart == permissionRevision {
            nextSyncState.permissionsBySessionID = Dictionary(grouping: bootstrap.permissions, by: \.sessionID)
        }
        if questionRevisionAtRequestStart == nil || questionRevisionAtRequestStart == questionRevision {
            nextSyncState.questionsBySessionID = Dictionary(grouping: bootstrap.questions, by: \.sessionID)
        }
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
            fallbackMessageCount: Self.immediateTranscriptMessageLimit,
            forSessionID: session.id
        )
        let syncedMessages = syncStore.messageEnvelopes(
            forSessionID: session.id,
            suffix: min(syncedVisibleMessageCount, Self.immediateTranscriptMessageLimit)
        )
        let cachedTail = Self.immediateTranscript(in: cachedMessages)
        let visibleMessages = syncedMessages.isEmpty ? cachedTail : syncedMessages

        if syncedMessageCount == 0, !cachedMessages.isEmpty {
            syncStore.state.replaceMessages(cachedMessages, forSessionID: session.id)
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
                return Array(messages[index...].suffix(immediateTranscriptMessageLimit))
            }
        }
        if let oldestUserIndex {
            return Array(messages[oldestUserIndex...].suffix(immediateTranscriptMessageLimit))
        }
        return Array(messages.suffix(immediateTranscriptMessageLimit))
    }

    func applyTodos(_ todos: [OpenCodeTodo], forSessionID sessionID: String) {
        guard syncStore.state.todosBySessionID[sessionID] != todos else { return }
        syncStore.state.todosBySessionID[sessionID] = todos
    }

    @discardableResult
    func applySessionStatuses(_ statuses: [String: String]) -> Bool {
        var changed = false
        if sessionStatuses != statuses {
            sessionStatuses = statuses
            changed = true
        }
        if syncStore.state.sessionStatusesBySessionID != statuses {
            syncStore.state.sessionStatusesBySessionID = statuses
            changed = true
        }
        return changed
    }

    func applyCanonicalMessages(_ messages: [OpenCodeMessageEnvelope], forSessionID sessionID: String) {
        var nextState = syncStore.state
        nextState.replaceMessages(messages, forSessionID: sessionID)
        guard nextState != syncStore.state else { return }
        syncStore.state = nextState
    }

    func applyCachedMessageState(_ cached: OpenCodeCachedMessageState, forSessionID sessionID: String) {
        var nextState = syncStore.state
        let previousMessageIDs = Set(nextState.messagesBySessionID[sessionID]?.map(\.id) ?? [])
        let nextMessageIDs = Set(cached.messages.map(\.id))
        for messageID in previousMessageIDs.subtracting(nextMessageIDs) {
            nextState.partsByMessageID[messageID] = nil
        }
        nextState.messagesBySessionID[sessionID] = cached.messages
        for (messageID, parts) in cached.partsByMessageID {
            nextState.partsByMessageID[messageID] = parts
        }
        syncStore.state = nextState
    }

    @discardableResult
    func applyCachedSessions(_ cachedSessions: [OpenCodeSession]) -> Bool {
        var changed = false
        if isLoadingSessions {
            isLoadingSessions = false
            changed = true
        }
        if sessions != cachedSessions {
            sessions = cachedSessions
            changed = true
        }
        let cachedRootCount = cachedSessions.lazy.filter(\.isRootSession).count
        if sessionTotal < cachedRootCount {
            sessionTotal = cachedRootCount
            changed = true
        }
        return changed
    }

    @discardableResult
    func upsertSessions(_ incomingSessions: [OpenCodeSession]) -> Bool {
        var nextSessions = sessions
        for incoming in incomingSessions {
            if let index = nextSessions.firstIndex(where: { $0.id == incoming.id }) {
                nextSessions[index] = nextSessions[index].merged(with: incoming)
            } else {
                nextSessions.append(incoming)
            }
        }
        guard nextSessions != sessions else { return false }
        sessions = nextSessions
        sessionTotal = max(sessionTotal, nextSessions.lazy.filter(\.isRootSession).count)
        return true
    }

    var hasMoreSessions: Bool {
        sessionTotal > sessions.lazy.filter(\.isRootSession).count
    }

    func appendMessage(_ message: OpenCodeMessageEnvelope, forSessionID sessionID: String) {
        syncStore.state.appendMessageEnvelope(message, forSessionID: sessionID)
    }

    @discardableResult
    func removeMessage(sessionID: String, messageID: String) -> Bool {
        syncStore.state.removeMessage(sessionID: sessionID, messageID: messageID)
    }

    @discardableResult
    func applyPermissions(_ permissions: [OpenCodePermission], ifUnchangedSince revision: UInt) -> Bool {
        guard permissionRevision == revision else { return false }
        let grouped = Dictionary(grouping: permissions, by: \.sessionID)
        guard syncStore.state.permissionsBySessionID != grouped else { return true }
        syncStore.state.permissionsBySessionID = grouped
        return true
    }

    func clearPermissions() {
        guard !syncStore.state.permissionsBySessionID.isEmpty else { return }
        syncStore.state.permissionsBySessionID = [:]
    }

    @discardableResult
    func applyQuestions(_ questions: [OpenCodeQuestionRequest], ifUnchangedSince revision: UInt) -> Bool {
        guard questionRevision == revision else { return false }
        let grouped = Dictionary(grouping: questions, by: \.sessionID)
        guard syncStore.state.questionsBySessionID != grouped else { return true }
        syncStore.state.questionsBySessionID = grouped
        return true
    }

    func clearQuestions() {
        guard !syncStore.state.questionsBySessionID.isEmpty else { return }
        syncStore.state.questionsBySessionID = [:]
    }

    func recordInteractionEvent(_ event: OpenCodeTypedEvent) {
        switch event {
        case .permissionAsked, .permissionReplied:
            permissionRevision &+= 1
        case .questionAsked, .questionReplied, .questionRejected:
            questionRevision &+= 1
        default:
            break
        }
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

        let deduplicatedSessions = Self.deduplicatedSessions(scopedSessions)
        if deduplicatedSessions != sessions {
            sessions = deduplicatedSessions
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

    private static func deduplicatedSessions(_ sessions: [OpenCodeSession]) -> [OpenCodeSession] {
        var result: [OpenCodeSession] = []
        var indexByID: [String: Int] = [:]
        for session in sessions {
            if let index = indexByID[session.id] {
                result[index] = result[index].merged(with: session)
            } else {
                indexByID[session.id] = result.count
                result.append(session)
            }
        }
        return result
    }
}
