import Combine
import XCTest
@testable import OpenClient

@MainActor
final class DirectoryStoreTests: XCTestCase {
    func testApplyDirectoryReloadOwnsSessionsCommandsStatusesAndInteractionSyncMaps() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        let permission = permission(id: "perm_1", sessionID: selected.id)
        let question = questionRequest(id: "q_1", sessionID: selected.id)
        let command = OpenCodeCommand(
            name: "review",
            description: "Review changes",
            agent: nil,
            model: nil,
            source: "project",
            template: "review",
            subtask: false,
            hints: []
        )
        let bootstrap = OpenCodeDirectoryBootstrap(
            sessions: [selected],
            sessionTotal: 2,
            sessionLimit: 100,
            commands: [command],
            permissions: [permission],
            questions: [question]
        )
        let store = DirectoryStore(isLoadingSessions: true)

        let changed = store.applyDirectoryReload(
            bootstrap: bootstrap,
            statuses: [selected.id: "busy"],
            scopedSessions: [selected]
        )

        XCTAssertTrue(changed)
        XCTAssertFalse(store.isLoadingSessions)
        XCTAssertEqual(store.sessions, [selected])
        XCTAssertEqual(store.sessionTotal, 2)
        XCTAssertEqual(store.sessionLimit, 100)
        XCTAssertTrue(store.hasMoreSessions)
        XCTAssertEqual(store.commands, [command])
        XCTAssertEqual(store.sessionStatuses, [selected.id: "busy"])
        XCTAssertEqual(store.syncState.sessionStatusesBySessionID, [selected.id: "busy"])
        XCTAssertEqual(store.syncState.permissionsBySessionID[selected.id], [permission])
        XCTAssertEqual(store.syncState.questionsBySessionID[selected.id], [question])
    }

    func testRootReloadPreservesKnownChildSessions() {
        let root = session(id: "ses_root", directory: "/tmp/project")
        let child = OpenCodeSession(
            id: "ses_child",
            title: "Child",
            workspaceID: nil,
            directory: "/tmp/project",
            projectID: nil,
            parentID: root.id
        )
        let store = DirectoryStore(sessions: [root, child])
        let bootstrap = OpenCodeDirectoryBootstrap(
            sessions: [root],
            sessionTotal: 1,
            sessionLimit: 100,
            commands: [],
            permissions: [],
            questions: []
        )

        store.applyDirectoryReload(bootstrap: bootstrap, statuses: [:], scopedSessions: [root])

        XCTAssertEqual(store.sessions.map(\.id), [root.id, child.id])
        XCTAssertEqual(store.sessionTotal, 1)
        XCTAssertFalse(store.hasMoreSessions)
    }

    func testStaleDirectoryBootstrapDoesNotEraseNewerPermissionOrQuestionEvents() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        let permission = permission(id: "perm_live", sessionID: selected.id)
        let question = questionRequest(id: "q_live", sessionID: selected.id)
        let store = DirectoryStore(sessions: [selected], selectedSession: selected)
        let permissionRevision = store.permissionRevision
        let questionRevision = store.questionRevision

        store.recordInteractionEvent(.permissionAsked(permission))
        XCTAssertTrue(store.applyPermissions([permission], ifUnchangedSince: store.permissionRevision))
        store.recordInteractionEvent(.questionAsked(question))
        XCTAssertTrue(store.applyQuestions([question], ifUnchangedSince: store.questionRevision))

        let staleBootstrap = OpenCodeDirectoryBootstrap(
            sessions: [selected],
            sessionTotal: 1,
            sessionLimit: 100,
            commands: [],
            permissions: [],
            questions: []
        )
        store.applyDirectoryReload(
            bootstrap: staleBootstrap,
            statuses: [:],
            scopedSessions: [selected],
            permissionRevisionAtRequestStart: permissionRevision,
            questionRevisionAtRequestStart: questionRevision
        )

        XCTAssertEqual(store.syncState.permissionsBySessionID[selected.id], [permission])
        XCTAssertEqual(store.syncState.questionsBySessionID[selected.id], [question])
    }

    func testCanonicalMessagesDeduplicateMessageAndPartIDs() {
        let selectedID = "ses_selected"
        let first = message(id: "msg_duplicate", role: "assistant", text: "First", sessionID: selectedID)
        let replacement = message(id: "msg_duplicate", role: "assistant", text: "Replacement", sessionID: selectedID)
        var duplicatePartReplacement = replacement
        duplicatePartReplacement.parts.append(replacement.parts[0])
        let store = DirectoryStore()

        store.applyCanonicalMessages([first, duplicatePartReplacement], forSessionID: selectedID)

        let messages = store.syncState.messageEnvelopes(forSessionID: selectedID)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].parts.count, 1)
        XCTAssertEqual(messages[0].parts[0].text, "Replacement")
    }

    func testApplySelectedSessionAfterReloadUpdatesOnlyWhenSelectionChanges() {
        let selected = session(id: "ses_selected", directory: nil)
        let store = DirectoryStore(selectedSession: selected)

        XCTAssertFalse(store.applySelectedSessionAfterReload(selected))
        XCTAssertTrue(store.applySelectedSessionAfterReload(nil))
        XCTAssertNil(store.selectedSession)
    }

    func testApplySessionSelectionUsesSyncedMessagesBeforeCachedMessages() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        let synced = message(id: "msg_synced", role: "assistant", text: "Synced", sessionID: selected.id)
        let cached = message(id: "msg_cached", role: "assistant", text: "Cached", sessionID: selected.id)
        let store = DirectoryStore()
        store.syncState.replaceMessages([synced], forSessionID: selected.id)

        let visible = store.applySessionSelection(selected, cachedMessages: [cached])

        XCTAssertEqual(store.selectedSession, selected)
        XCTAssertEqual(visible.map(\.id), ["msg_synced"])
        XCTAssertEqual(store.syncState.messageEnvelopes(forSessionID: selected.id).map(\.id), ["msg_synced"])
    }

    func testApplySessionSelectionSeedsSyncStateFromCacheWhenSyncedMessagesAreEmpty() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        let cached = message(id: "msg_cached", role: "assistant", text: "Cached", sessionID: selected.id)
        let store = DirectoryStore()

        let visible = store.applySessionSelection(selected, cachedMessages: [cached])

        XCTAssertEqual(store.selectedSession, selected)
        XCTAssertEqual(visible.map(\.id), ["msg_cached"])
        XCTAssertEqual(store.syncState.messageEnvelopes(forSessionID: selected.id).map(\.id), ["msg_cached"])
    }

    func testApplySessionSelectionSeedsFullSyncStateWhileShowingOnlyLatestCachedRound() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        let cached = (0..<8).flatMap { round in
            [
                message(id: "msg_\(round)_user", role: "user", text: "Prompt \(round)", sessionID: selected.id),
                message(id: "msg_\(round)_assistant", role: "assistant", text: "Answer \(round)", sessionID: selected.id),
            ]
        }
        let store = DirectoryStore()

        let visible = store.applySessionSelection(selected, cachedMessages: cached)

        XCTAssertEqual(visible.count, 2)
        XCTAssertEqual(store.syncState.messageCount(forSessionID: selected.id), cached.count)
    }

    func testApplySessionSelectionPreparesOnlyLatestUserRound() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        var messages: [OpenCodeMessageEnvelope] = []
        for round in 0..<20 {
            messages.append(message(id: String(format: "msg_%03d_user", round * 2), role: "user", text: "Prompt \(round)", sessionID: selected.id))
            messages.append(message(id: String(format: "msg_%03d_assistant", round * 2 + 1), role: "assistant", text: "Answer \(round)", sessionID: selected.id))
        }
        let store = DirectoryStore()
        store.syncState.replaceMessages(messages, forSessionID: selected.id)

        let visible = store.applySessionSelection(selected, cachedMessages: [])

        XCTAssertEqual(visible.map(\.id), [
            "msg_038_user", "msg_039_assistant",
        ])
        XCTAssertEqual(store.syncState.messageCount(forSessionID: selected.id), 40)
    }

    func testApplySessionSelectionCapsAnOversizedLatestRound() {
        let selected = session(id: "ses_selected", directory: "/tmp/project")
        let messages = [
            message(id: "msg_000_user", role: "user", text: "Prompt", sessionID: selected.id),
        ] + (1...20).map { index in
            message(
                id: String(format: "msg_%03d_assistant", index),
                role: "assistant",
                text: "Step \(index)",
                sessionID: selected.id
            )
        }
        let store = DirectoryStore()
        store.syncState.replaceMessages(messages, forSessionID: selected.id)

        let visible = store.applySessionSelection(selected, cachedMessages: [])

        XCTAssertEqual(visible.count, 12)
        XCTAssertEqual(visible.last?.id, "msg_020_assistant")
        XCTAssertEqual(store.syncState.messageCount(forSessionID: selected.id), 21)
    }

    func testApplyInteractionHydrationResultsUpdatesSyncState() {
        let selectedID = "ses_selected"
        let otherID = "ses_other"
        let selectedTodo = OpenCodeTodo(content: "Selected", status: "pending", priority: "high")
        let selectedPermission = permission(id: "perm_selected", sessionID: selectedID)
        let otherPermission = permission(id: "perm_other", sessionID: otherID)
        let selectedQuestion = questionRequest(id: "q_selected", sessionID: selectedID)
        let otherQuestion = questionRequest(id: "q_other", sessionID: otherID)
        let store = DirectoryStore()

        store.applyTodos([selectedTodo], forSessionID: selectedID)
        store.applyPermissions([selectedPermission, otherPermission], ifUnchangedSince: store.permissionRevision)
        store.applyQuestions([selectedQuestion, otherQuestion], ifUnchangedSince: store.questionRevision)

        XCTAssertEqual(store.syncState.todosBySessionID[selectedID], [selectedTodo])
        XCTAssertEqual(store.syncState.permissionsBySessionID[selectedID], [selectedPermission])
        XCTAssertEqual(store.syncState.permissionsBySessionID[otherID], [otherPermission])
        XCTAssertEqual(store.syncState.questionsBySessionID[selectedID], [selectedQuestion])
        XCTAssertEqual(store.syncState.questionsBySessionID[otherID], [otherQuestion])

        store.clearPermissions()
        store.clearQuestions()

        XCTAssertTrue(store.syncState.permissionsBySessionID.isEmpty)
        XCTAssertTrue(store.syncState.questionsBySessionID.isEmpty)
    }

    func testApplySessionStatusesMirrorsDirectoryAndSyncState() {
        let store = DirectoryStore(sessionStatuses: ["ses_stale": "busy"])

        XCTAssertTrue(store.applySessionStatuses(["ses_selected": "idle"]))

        XCTAssertEqual(store.sessionStatuses, ["ses_selected": "idle"])
        XCTAssertEqual(store.syncState.sessionStatusesBySessionID, ["ses_selected": "idle"])
    }

    func testApplySessionStatusesDoesNotPublishWhenStateIsUnchanged() {
        let store = DirectoryStore()
        XCTAssertTrue(store.applySessionStatuses(["ses_selected": "idle"]))
        var publicationCount = 0
        let observation = store.objectWillChange.sink { publicationCount += 1 }

        XCTAssertFalse(store.applySessionStatuses(["ses_selected": "idle"]))

        XCTAssertEqual(publicationCount, 0)
        withExtendedLifetime(observation) {}
    }

    func testApplyCanonicalMessagesReplacesSessionTranscriptInSyncState() {
        let selectedID = "ses_selected"
        let initial = message(id: "msg_initial", role: "assistant", text: "Initial", sessionID: selectedID)
        let loaded = message(id: "msg_loaded", role: "assistant", text: "Loaded", sessionID: selectedID)
        let store = DirectoryStore()
        store.syncState.replaceMessages([initial], forSessionID: selectedID)

        store.applyCanonicalMessages([loaded], forSessionID: selectedID)

        XCTAssertEqual(store.syncState.messageEnvelopes(forSessionID: selectedID).map(\.id), ["msg_loaded"])
    }

    func testAppendAndRemoveMessageUpdatesSessionTranscriptInSyncState() {
        let sessionID = "ses_selected"
        let message = message(id: "msg_optimistic", role: "user", text: "Hello", sessionID: sessionID)
        let store = DirectoryStore()

        store.appendMessage(message, forSessionID: sessionID)
        XCTAssertEqual(store.syncState.messageEnvelopes(forSessionID: sessionID).map(\.id), ["msg_optimistic"])

        XCTAssertTrue(store.removeMessage(sessionID: sessionID, messageID: message.id))
        XCTAssertTrue(store.syncState.messageEnvelopes(forSessionID: sessionID).isEmpty)
    }

    func testRegistryNormalizesDirectoryKeysWithoutConflatingRootAndGlobal() {
        XCTAssertEqual(DirectoryStoreRegistry.key(for: nil), "global")
        XCTAssertEqual(DirectoryStoreRegistry.key(for: ""), "global")
        XCTAssertEqual(DirectoryStoreRegistry.key(for: "global"), "global")
        XCTAssertEqual(DirectoryStoreRegistry.key(for: "/tmp/project/"), "/tmp/project")
        XCTAssertEqual(DirectoryStoreRegistry.key(for: "\\tmp\\project\\"), "/tmp/project")
        XCTAssertEqual(DirectoryStoreRegistry.key(for: "/"), "/")
    }

    func testRegistryRetainsDirectoryStateAcrossActivation() {
        let registry = DirectoryStoreRegistry()
        let projectA = registry.activate("/tmp/a")
        projectA.sessions = [session(id: "ses_a", directory: "/tmp/a")]

        let projectB = registry.activate("/tmp/b")
        projectB.sessions = [session(id: "ses_b", directory: "/tmp/b")]

        XCTAssertTrue(registry.activate("/tmp/a") === projectA)
        XCTAssertEqual(registry.activeStore.sessions.map(\.id), ["ses_a"])
        XCTAssertTrue(registry.activate("/tmp/b") === projectB)
        XCTAssertEqual(registry.activeStore.sessions.map(\.id), ["ses_b"])
    }

    func testRegistryRestoresSelectionAndTranscriptAcrossDirectoryActivation() {
        let registry = DirectoryStoreRegistry(activeDirectory: "/tmp/a")
        let sessionA = session(id: "ses_a", directory: "/tmp/a")
        let messageA = message(id: "msg_a", role: "assistant", text: "Project A", sessionID: sessionA.id)
        registry.activeStore.sessions = [sessionA]
        _ = registry.activeStore.applySessionSelection(sessionA, cachedMessages: [messageA])

        let sessionB = session(id: "ses_b", directory: "/tmp/b")
        let messageB = message(id: "msg_b", role: "assistant", text: "Project B", sessionID: sessionB.id)
        let storeB = registry.activate("/tmp/b")
        storeB.sessions = [sessionB]
        _ = storeB.applySessionSelection(sessionB, cachedMessages: [messageB])

        let restoredA = registry.activate("/tmp/a")

        XCTAssertEqual(restoredA.selectedSession?.id, sessionA.id)
        XCTAssertEqual(restoredA.syncState.messageEnvelopes(forSessionID: sessionA.id), [messageA])
        XCTAssertEqual(storeB.selectedSession?.id, sessionB.id)
        XCTAssertEqual(storeB.syncState.messageEnvelopes(forSessionID: sessionB.id), [messageB])
    }

    func testRegistryFindsSessionAndMessageOwners() {
        let registry = DirectoryStoreRegistry(activeDirectory: "/tmp/a")
        let owner = registry.activeStore
        let ownedSession = session(id: "ses_a", directory: "/tmp/a")
        owner.sessions = [ownedSession]
        owner.applyCanonicalMessages(
            [message(id: "msg_a", role: "assistant", text: "A", sessionID: ownedSession.id)],
            forSessionID: ownedSession.id
        )

        XCTAssertTrue(registry.ownerStore(forSessionID: ownedSession.id) === owner)
        XCTAssertEqual(registry.stores(containingMessageID: "msg_a").count, 1)
    }

    func testDirectorySyncFacadeRoutesKnownSessionOnlyToExistingOwner() {
        let registry = DirectoryStoreRegistry(activeDirectory: "/tmp/project")
        let owner = registry.activeStore
        let ownedSession = session(id: "ses_project", directory: "/tmp/project")
        owner.sessions = [ownedSession]
        let global = registry.store(for: nil)
        let facade = DirectorySyncFacade(registry: registry, coordinator: EventSyncCoordinator())
        let managed = OpenCodeManagedEvent(
            directory: DirectoryStoreRegistry.globalKey,
            envelope: OpenCodeEventEnvelope(
                type: "session.status",
                properties: OpenCodeEventProperties(sessionID: ownedSession.id)
            ),
            typed: .sessionStatus(sessionID: ownedSession.id, status: "busy")
        )

        let targets = facade.targetStores(
            for: managed,
            selectedSessionID: nil,
            selectedSessionDirectory: nil,
            effectiveSelectedDirectory: "/tmp/project",
            activeLiveActivitySessionIDs: []
        )

        XCTAssertEqual(targets.count, 1)
        XCTAssertTrue(targets.first === owner)
        XCTAssertFalse(targets.contains { $0 === global })
    }

    func testDirectorySyncFacadeUsesEventDirectoryStoreWhenSessionHasNoOwner() {
        let registry = DirectoryStoreRegistry(activeDirectory: "/tmp/a")
        let eventStore = registry.store(for: "/tmp/b")
        let created = session(id: "ses_b", directory: "/tmp/b")
        let facade = DirectorySyncFacade(registry: registry, coordinator: EventSyncCoordinator())
        let managed = OpenCodeManagedEvent(
            directory: "/tmp/b",
            envelope: OpenCodeEventEnvelope(
                type: "session.created",
                properties: OpenCodeEventProperties(sessionID: created.id)
            ),
            typed: .sessionCreated(created)
        )

        let targets = facade.targetStores(
            for: managed,
            selectedSessionID: nil,
            selectedSessionDirectory: nil,
            effectiveSelectedDirectory: "/tmp/a",
            activeLiveActivitySessionIDs: []
        )

        XCTAssertEqual(targets.count, 1)
        XCTAssertTrue(targets.first === eventStore)
        XCTAssertFalse(targets.contains { $0 === registry.activeStore })
    }

    func testRegistryResetDropsRetainedStoresAndReturnsToGlobal() {
        let registry = DirectoryStoreRegistry(activeDirectory: "/tmp/a")
        let oldStore = registry.activeStore
        oldStore.sessions = [session(id: "ses_a", directory: "/tmp/a")]

        registry.reset()

        XCTAssertEqual(registry.activeKey, DirectoryStoreRegistry.globalKey)
        XCTAssertFalse(registry.activeStore === oldStore)
        XCTAssertEqual(registry.generation, 1)
        XCTAssertTrue(registry.activeStore.sessions.isEmpty)
        XCTAssertNil(registry.existingStore(for: "/tmp/a"))
        XCTAssertFalse(registry.contains(oldStore, forKey: "/tmp/a"))
    }

    private func session(id: String, directory: String?) -> OpenCodeSession {
        OpenCodeSession(id: id, title: "Session", workspaceID: nil, directory: directory, projectID: nil, parentID: nil)
    }

    private func message(id: String, role: String, text: String, sessionID: String) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: id, role: role, sessionID: sessionID, time: nil, agent: nil, model: nil),
            parts: [
                OpenCodePart(id: "part_\(id)", messageID: id, sessionID: sessionID, type: "text", mime: nil, filename: nil, url: nil, reason: nil, tool: nil, callID: nil, state: nil, text: text)
            ]
        )
    }

    private func permission(id: String, sessionID: String) -> OpenCodePermission {
        OpenCodePermission(
            id: id,
            sessionID: sessionID,
            permission: "bash",
            patterns: ["bash"],
            always: nil,
            metadata: nil,
            tool: nil
        )
    }

    private func questionRequest(id: String, sessionID: String) -> OpenCodeQuestionRequest {
        OpenCodeQuestionRequest(
            id: id,
            sessionID: sessionID,
            questions: [
                OpenCodeQuestion(
                    question: "Choose",
                    header: "Question",
                    options: [OpenCodeQuestionOption(label: "Yes", description: "Continue")]
                )
            ],
            tool: nil
        )
    }
}
