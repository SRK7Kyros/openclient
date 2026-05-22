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
        XCTAssertEqual(store.commands, [command])
        XCTAssertEqual(store.sessionStatuses, [selected.id: "busy"])
        XCTAssertEqual(store.syncState.permissionsBySessionID[selected.id], [permission])
        XCTAssertEqual(store.syncState.questionsBySessionID[selected.id], [question])
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
        store.applyPermissions([selectedPermission, otherPermission])
        store.applyQuestions([selectedQuestion, otherQuestion])

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

        store.applySessionStatuses(["ses_selected": "idle"])

        XCTAssertEqual(store.sessionStatuses, ["ses_selected": "idle"])
        XCTAssertEqual(store.syncState.sessionStatusesBySessionID, ["ses_selected": "idle"])
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
