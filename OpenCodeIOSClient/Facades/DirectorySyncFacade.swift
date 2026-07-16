import Foundation

@MainActor
final class DirectorySyncFacade {
    struct AppliedEvent {
        let store: DirectoryStore
        let application: EventSyncCoordinator.DirectoryEventApplication
        let changedStore: Bool
    }

    private let registry: DirectoryStoreRegistry
    private let coordinator: EventSyncCoordinator

    init(registry: DirectoryStoreRegistry, coordinator: EventSyncCoordinator) {
        self.registry = registry
        self.coordinator = coordinator
    }

    func apply(
        _ managed: OpenCodeManagedEvent,
        activeState: EventSyncCoordinator.DirectoryEventState,
        selectedSessionID: String?,
        selectedSessionDirectory: String?,
        effectiveSelectedDirectory: String?,
        activeLiveActivitySessionIDs: Set<String>,
        scopedSessions: ([OpenCodeSession], String?) -> [OpenCodeSession]
    ) -> [AppliedEvent] {
        targetStores(
            for: managed,
            selectedSessionID: selectedSessionID,
            selectedSessionDirectory: selectedSessionDirectory,
            effectiveSelectedDirectory: effectiveSelectedDirectory,
            activeLiveActivitySessionIDs: activeLiveActivitySessionIDs
        ).map { store in
            let state = store === registry.activeStore ? activeState : directoryState(for: store)
            let application = coordinator.applyDirectoryEvent(managed, to: state)
            let directory = registry.key(for: store).flatMap(DirectoryStoreRegistry.directory(forKey:))
            let changed = store.applyReducedEventState(
                application.state,
                scopedSessions: scopedSessions(application.state.sessions, directory)
            )
            return AppliedEvent(store: store, application: application, changedStore: changed)
        }
    }

    func targetStores(
        for managed: OpenCodeManagedEvent,
        selectedSessionID: String?,
        selectedSessionDirectory: String?,
        effectiveSelectedDirectory: String?,
        activeLiveActivitySessionIDs: Set<String>
    ) -> [DirectoryStore] {
        let sessionID = coordinator.sessionID(for: managed.typed)
        var stores: [DirectoryStore] = []

        if let sessionID {
            if let owner = registry.ownerStore(forSessionID: sessionID) {
                stores.append(owner)
            }
        } else if case let .messagePartRemoved(messageID, _) = managed.typed {
            if let owner = registry.stores(containingMessageID: messageID).first {
                stores.append(owner)
            }
        }

        let eventDirectory = managed.directory == DirectoryStoreRegistry.globalKey ? nil : managed.directory
        if stores.isEmpty {
            if let existing = registry.existingStore(for: eventDirectory) {
                stores.append(existing)
            } else if let sessionID, activeLiveActivitySessionIDs.contains(sessionID) {
                stores.append(registry.store(for: eventDirectory))
            }
        }

        if stores.isEmpty, coordinator.shouldApplyDirectoryEvent(
            eventDirectory: managed.directory,
            eventSessionID: sessionID,
            selectedSessionID: selectedSessionID,
            selectedSessionDirectory: selectedSessionDirectory,
            effectiveSelectedDirectory: effectiveSelectedDirectory,
            activeLiveActivitySessionIDs: activeLiveActivitySessionIDs
        ) {
            stores.append(registry.activeStore)
        }

        if stores.isEmpty, managed.directory == DirectoryStoreRegistry.globalKey, sessionID != nil {
            stores.append(registry.store(for: nil))
        }

        var seen: Set<ObjectIdentifier> = []
        return stores.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private func directoryState(for store: DirectoryStore) -> EventSyncCoordinator.DirectoryEventState {
        let selectedSessionID = store.selectedSession?.id
        return EventSyncCoordinator.DirectoryEventState(
            sessions: store.sessions,
            selectedSession: store.selectedSession,
            sessionStatuses: store.sessionStatuses,
            syncState: store.syncState,
            messages: selectedSessionID.map { store.syncState.messageEnvelopes(forSessionID: $0) } ?? [],
            todos: selectedSessionID.flatMap { store.syncState.todosBySessionID[$0] } ?? [],
            permissions: selectedSessionID.flatMap { store.syncState.permissionsBySessionID[$0] } ?? [],
            questions: selectedSessionID.flatMap { store.syncState.questionsBySessionID[$0] } ?? []
        )
    }
}
