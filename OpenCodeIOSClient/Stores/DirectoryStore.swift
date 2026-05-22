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
