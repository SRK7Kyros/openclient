import Foundation

extension AppViewModel {
    var usesLocalCache: Bool {
        !isUsingAppleIntelligence
    }

    var isBrowsingLocalCache: Bool {
        backendMode == .cachedServer
    }

    func resetLocalCacheRuntimeState() {
        localCacheWriteTasksByKey.values.forEach { $0.cancel() }
        localCacheWriteTasksByKey = [:]
        localCacheDirectoryRefreshedAtByKey = [:]
        localCacheMessageRefreshedAtByKey = [:]
        localCacheTodoRefreshedAtByKey = [:]
        localCacheHydratedChatKeys = []
        localCachePrefetchTasksByKey.values.forEach { $0.cancel() }
        localCachePrefetchTasksByKey = [:]
        localCachePrefetchedChatsByKey = [:]
        localCachePrefetchedChatKeys = []
    }

    func loadCachedProjectsIfEnabled() async -> OpenCodeCachedProjectsSnapshot? {
        guard usesLocalCache, config.hasCredentials else { return nil }
        return try? await localCacheRepository.loadProjects(serverID: config.recentServerID)
    }

    func persistProjectsToLocalCache() {
        guard usesLocalCache, config.hasCredentials else { return }
        let repository = localCacheRepository
        let serverID = config.recentServerID
        let snapshot = projects
        let writtenAt = Date()
        Task {
            try? await repository.saveProjects(
                snapshot,
                serverID: serverID,
                refreshedAt: writtenAt,
                writtenAt: writtenAt
            )
        }
    }

    @discardableResult
    func hydrateDirectoryFromLocalCache(_ directory: String?) async -> OpenCodeCachedDirectorySessionsSnapshot? {
        guard usesLocalCache, config.hasCredentials else { return nil }
        let serverID = config.recentServerID
        let targetKey = DirectoryStoreRegistry.key(for: directory)
        let targetStore = directoryStoreRegistry.store(for: directory)
        let targetGeneration = directoryStoreRegistry.generation
        let initialSessions = targetStore.sessions
        guard let snapshot = try? await localCacheRepository.loadDirectorySessions(
            serverID: serverID,
            directory: directory
        ) else { return nil }
        guard !Task.isCancelled,
              config.recentServerID == serverID,
              directoryStoreRegistry.generation == targetGeneration,
              directoryStoreRegistry.contains(targetStore, forKey: targetKey),
              targetStore.sessions == initialSessions else { return nil }

        if initialSessions.isEmpty {
            let scopedSessions = sessionListStore.applyDirectoryReloadSessions(snapshot.sessions, scopedTo: directory)
            if targetStore.applyCachedSessions(scopedSessions), targetStore === directoryStore {
                objectWillChange.send()
            }
        }
        if let statuses = snapshot.statuses {
            _ = targetStore.applySessionStatuses(statuses)
        }
        if let permissions = snapshot.permissions {
            _ = targetStore.applyPermissions(permissions, ifUnchangedSince: targetStore.permissionRevision)
        }
        if let questions = snapshot.questions {
            _ = targetStore.applyQuestions(questions, ifUnchangedSince: targetStore.questionRevision)
        }
        localCacheDirectoryRefreshedAtByKey[localCacheRuntimeKey(serverID: serverID, value: targetKey)] = snapshot.refreshedAt
        return snapshot
    }

    func persistDirectoryToLocalCache(
        _ store: DirectoryStore,
        directory: String?,
        marksValidated: Bool = true
    ) {
        guard usesLocalCache, config.hasCredentials else { return }
        let repository = localCacheRepository
        let serverID = config.recentServerID
        let sessions = store.sessions
        let statuses = store.sessionStatuses
        let permissions = store.syncState.permissionsBySessionID.values
            .flatMap { $0 }
            .sorted { $0.id < $1.id }
        let questions = store.syncState.questionsBySessionID.values
            .flatMap { $0 }
            .sorted { $0.id < $1.id }
        let runtimeKey = localCacheRuntimeKey(
            serverID: serverID,
            value: DirectoryStoreRegistry.key(for: directory)
        )
        let refreshedAt = marksValidated
            ? Date()
            : (localCacheDirectoryRefreshedAtByKey[runtimeKey] ?? .distantPast)
        let writtenAt = Date()
        if marksValidated {
            localCacheDirectoryRefreshedAtByKey[runtimeKey] = refreshedAt
        }
        Task {
            try? await repository.saveDirectorySessions(
                sessions,
                serverID: serverID,
                directory: directory,
                refreshedAt: refreshedAt,
                writtenAt: writtenAt
            )
            try? await repository.saveDirectoryMetadata(
                statuses: statuses,
                permissions: permissions,
                questions: questions,
                serverID: serverID,
                directory: directory,
                refreshedAt: refreshedAt,
                writtenAt: writtenAt
            )
        }
    }

    @discardableResult
    func hydrateChatFromLocalCache(
        _ session: OpenCodeSession,
        navigationGeneration: UInt? = nil,
        expectedDirectoryKey: String? = nil
    ) async -> OpenCodeCachedChatSnapshot? {
        guard usesLocalCache, config.hasCredentials else { return nil }
        let serverID = config.recentServerID
        let targetStore = directoryStoreRegistry.ownerStore(forSessionID: session.id) ?? directoryStore
        let targetGeneration = directoryStoreRegistry.generation
        let hadInitialMessages = targetStore.syncStore.messageCount(forSessionID: session.id) > 0
        let initialTodos = targetStore.syncState.todosBySessionID[session.id]
        let snapshot = await localChatSnapshot(
            serverID: serverID,
            sessionID: session.id,
            consumesPrefetch: true
        )

        guard !Task.isCancelled,
              config.recentServerID == serverID,
              directoryStoreRegistry.generation == targetGeneration,
              directoryStoreRegistry.key(for: targetStore) != nil,
              navigationGeneration == nil || sessionNavigationGeneration == navigationGeneration,
              expectedDirectoryKey == nil || directoryStoreRegistry.activeKey == expectedDirectoryKey,
              selectedSession?.id == session.id else { return nil }
        let runtimeKey = localCacheRuntimeKey(serverID: serverID, value: session.id)
        localCacheHydratedChatKeys.insert(runtimeKey)
        guard let snapshot else { return nil }
        let appliedMessages = !hadInitialMessages
            && targetStore.syncStore.messageCount(forSessionID: session.id) == 0
            && (!snapshot.preparedMessages.messages.isEmpty || snapshot.messagesRefreshedAt != nil)
        if appliedMessages {
            targetStore.applyCachedMessageState(snapshot.preparedMessages, forSessionID: session.id)
            chatStore.cacheMessages(snapshot.preparedMessages.immediateMessages, forSessionID: session.id)
        }
        let appliedTodos = targetStore.syncState.todosBySessionID[session.id] == initialTodos
            && (!snapshot.todos.isEmpty || snapshot.todosRefreshedAt != nil)
        if appliedTodos {
            targetStore.applyTodos(snapshot.todos, forSessionID: session.id)
            sessionInteractionStore.applyTodos(
                snapshot.todos,
                forSessionID: session.id,
                selectedSessionID: selectedSession?.id
            )
        }

        if appliedMessages {
            localCacheMessageRefreshedAtByKey[runtimeKey] = snapshot.messagesRefreshedAt
        }
        if appliedTodos {
            localCacheTodoRefreshedAtByKey[runtimeKey] = snapshot.todosRefreshedAt
        }
        return snapshot
    }

    private func localChatSnapshot(
        serverID: String,
        sessionID: String,
        consumesPrefetch: Bool = false
    ) async -> OpenCodeCachedChatSnapshot? {
        let key = localCacheRuntimeKey(serverID: serverID, value: sessionID)
        if let snapshot = localCachePrefetchedChatsByKey[key] {
            if consumesPrefetch {
                removePrefetchedChat(key)
            } else {
                touchPrefetchedChat(key)
            }
            return snapshot
        }

        let task: Task<OpenCodeCachedChatSnapshot?, Never>
        if let existingTask = localCachePrefetchTasksByKey[key] {
            task = existingTask
        } else {
            let repository = localCacheRepository
            task = Task {
                try? await repository.loadChat(serverID: serverID, sessionID: sessionID)
            }
            localCachePrefetchTasksByKey[key] = task
        }

        let snapshot = await task.value
        guard !task.isCancelled, config.recentServerID == serverID else { return nil }
        localCachePrefetchTasksByKey[key] = nil
        if let snapshot, !consumesPrefetch {
            localCachePrefetchedChatsByKey[key] = snapshot
            touchPrefetchedChat(key)
        }
        return snapshot
    }

    private func touchPrefetchedChat(_ key: String) {
        localCachePrefetchedChatKeys.removeAll { $0 == key }
        localCachePrefetchedChatKeys.append(key)
        while localCachePrefetchedChatKeys.count > 1 {
            let removedKey = localCachePrefetchedChatKeys.removeFirst()
            localCachePrefetchedChatsByKey[removedKey] = nil
        }
    }

    private func removePrefetchedChat(_ key: String) {
        localCachePrefetchedChatsByKey[key] = nil
        localCachePrefetchedChatKeys.removeAll { $0 == key }
    }

    private func invalidatePrefetchedChat(serverID: String, sessionID: String) {
        let key = localCacheRuntimeKey(serverID: serverID, value: sessionID)
        localCachePrefetchTasksByKey[key]?.cancel()
        localCachePrefetchTasksByKey[key] = nil
        removePrefetchedChat(key)
    }

    func persistLoadedMessagesToLocalCache(_ messages: [OpenCodeMessageEnvelope], sessionID: String) {
        guard usesLocalCache, config.hasCredentials else { return }
        let repository = localCacheRepository
        let serverID = config.recentServerID
        invalidatePrefetchedChat(serverID: serverID, sessionID: sessionID)
        let runtimeKey = localCacheRuntimeKey(serverID: serverID, value: sessionID)
        let refreshedAt = Date()
        let writtenAt = refreshedAt
        localCacheMessageRefreshedAtByKey[runtimeKey] = refreshedAt
        Task {
            try? await repository.saveChatMessages(
                messages,
                serverID: serverID,
                sessionID: sessionID,
                refreshedAt: refreshedAt,
                writtenAt: writtenAt
            )
        }
    }

    func persistLoadedTodosToLocalCache(_ todos: [OpenCodeTodo], sessionID: String) {
        guard usesLocalCache, config.hasCredentials else { return }
        let repository = localCacheRepository
        let serverID = config.recentServerID
        let runtimeKey = localCacheRuntimeKey(serverID: serverID, value: sessionID)
        let refreshedAt = Date()
        let writtenAt = refreshedAt
        localCacheTodoRefreshedAtByKey[runtimeKey] = refreshedAt
        Task {
            try? await repository.saveTodos(
                todos,
                serverID: serverID,
                sessionID: sessionID,
                refreshedAt: refreshedAt,
                writtenAt: writtenAt
            )
        }
    }

    func scheduleLocalChatCacheWrite(
        sessionID: String,
        store: DirectoryStore,
        includesTodos: Bool,
        immediate: Bool = false
    ) {
        guard usesLocalCache, config.hasCredentials else { return }
        let serverID = config.recentServerID
        invalidatePrefetchedChat(serverID: serverID, sessionID: sessionID)
        let runtimeKey = localCacheRuntimeKey(serverID: serverID, value: sessionID)
        localCacheWriteTasksByKey[runtimeKey]?.cancel()
        let repository = localCacheRepository
        let syncState = store.syncState
        let messagesValidatedAt = localCacheMessageRefreshedAtByKey[runtimeKey] ?? .distantPast
        let todosValidatedAt = localCacheTodoRefreshedAtByKey[runtimeKey] ?? .distantPast
        let writtenAt = Date()

        localCacheWriteTasksByKey[runtimeKey] = Task.detached { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .seconds(5))
            }
            guard !Task.isCancelled else { return }
            let messages = syncState.messageEnvelopes(forSessionID: sessionID)
            let todos = syncState.todosBySessionID[sessionID] ?? []
            try? await repository.saveChatMessages(
                messages,
                serverID: serverID,
                sessionID: sessionID,
                refreshedAt: messagesValidatedAt,
                writtenAt: writtenAt
            )
            if includesTodos {
                try? await repository.saveTodos(
                    todos,
                    serverID: serverID,
                    sessionID: sessionID,
                    refreshedAt: todosValidatedAt,
                    writtenAt: writtenAt
                )
            }
            await MainActor.run { [weak self] in
                self?.localCacheWriteTasksByKey[runtimeKey] = nil
            }
        }
    }

    func removeSessionFromLocalCache(_ sessionID: String) {
        guard usesLocalCache, config.hasCredentials else { return }
        let repository = localCacheRepository
        let serverID = config.recentServerID
        invalidatePrefetchedChat(serverID: serverID, sessionID: sessionID)
        let runtimeKey = localCacheRuntimeKey(serverID: serverID, value: sessionID)
        localCacheWriteTasksByKey[runtimeKey]?.cancel()
        localCacheWriteTasksByKey[runtimeKey] = nil
        localCacheMessageRefreshedAtByKey[runtimeKey] = nil
        localCacheTodoRefreshedAtByKey[runtimeKey] = nil
        let removedAt = Date()
        Task {
            try? await repository.removeSession(
                serverID: serverID,
                sessionID: sessionID,
                removedAt: removedAt
            )
        }
    }

    func persistManagedEventToLocalCache(
        _ managed: OpenCodeManagedEvent,
        applications: [DirectorySyncFacade.AppliedEvent],
        sessionID: String?
    ) {
        guard usesLocalCache else { return }

        switch managed.typed {
        case .sessionStatus,
             .sessionIdle,
             .permissionAsked,
             .permissionReplied,
             .questionAsked,
             .questionReplied,
             .questionRejected:
            for application in applications {
                let directory = directoryStoreRegistry.key(for: application.store)
                    .flatMap(DirectoryStoreRegistry.directory(forKey:))
                persistDirectoryToLocalCache(
                    application.store,
                    directory: directory,
                    marksValidated: false
                )
            }
        default:
            break
        }

        switch managed.typed {
        case let .sessionDeleted(session):
            removeSessionFromLocalCache(session.id)
        case let .sessionUpdated(session) where session.isArchived:
            removeSessionFromLocalCache(session.id)
        case .sessionCreated, .sessionUpdated:
            for application in applications {
                let directory = directoryStoreRegistry.key(for: application.store)
                    .flatMap(DirectoryStoreRegistry.directory(forKey:))
                persistDirectoryToLocalCache(
                    application.store,
                    directory: directory,
                    marksValidated: false
                )
            }
        case .messageUpdated,
             .messagePartUpdated,
             .messagePartDelta,
             .messageRemoved:
            guard OpenCodeLocalCacheEventWritePolicy.writesChatSnapshot(for: managed.typed) else { return }
            guard let sessionID else { return }
            for application in applications {
                scheduleLocalChatCacheWrite(
                    sessionID: sessionID,
                    store: application.store,
                    includesTodos: false
                )
            }
        case let .messagePartRemoved(messageID, _):
            for application in applications {
                guard let ownerSessionID = application.store.syncState.messagesBySessionID.first(where: { _, messages in
                    messages.contains { $0.id == messageID }
                })?.key else { continue }
                scheduleLocalChatCacheWrite(
                    sessionID: ownerSessionID,
                    store: application.store,
                    includesTodos: false
                )
            }
        case .todoUpdated:
            guard let sessionID else { return }
            for application in applications {
                scheduleLocalChatCacheWrite(
                    sessionID: sessionID,
                    store: application.store,
                    includesTodos: true
                )
            }
        case .sessionIdle:
            guard let sessionID else { return }
            for application in applications {
                scheduleLocalChatCacheWrite(
                    sessionID: sessionID,
                    store: application.store,
                    includesTodos: application.store.syncState.todosBySessionID[sessionID] != nil,
                    immediate: true
                )
            }
        default:
            break
        }
    }

    func isLocalDirectoryCacheFresh(_ directory: String?) -> Bool {
        guard usesLocalCache else { return false }
        let key = localCacheRuntimeKey(
            serverID: config.recentServerID,
            value: DirectoryStoreRegistry.key(for: directory)
        )
        return OpenCodeLocalCacheFreshness.isFresh(localCacheDirectoryRefreshedAtByKey[key])
    }

    func areLocalChatMessagesFresh(sessionID: String) -> Bool {
        guard usesLocalCache else { return false }
        let key = localCacheRuntimeKey(serverID: config.recentServerID, value: sessionID)
        return OpenCodeLocalCacheFreshness.isFresh(localCacheMessageRefreshedAtByKey[key])
    }

    func areLocalChatTodosFresh(sessionID: String) -> Bool {
        guard usesLocalCache else { return false }
        let key = localCacheRuntimeKey(serverID: config.recentServerID, value: sessionID)
        return OpenCodeLocalCacheFreshness.isFresh(localCacheTodoRefreshedAtByKey[key])
    }

    func hasHydratedLocalChat(sessionID: String) -> Bool {
        let key = localCacheRuntimeKey(serverID: config.recentServerID, value: sessionID)
        return localCacheHydratedChatKeys.contains(key)
    }

    private func localCacheRuntimeKey(serverID: String, value: String) -> String {
        "s\(serverID.utf8.count):\(serverID)s\(value.utf8.count):\(value)"
    }
}
