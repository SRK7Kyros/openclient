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

    private func session(id: String, directory: String?) -> OpenCodeSession {
        OpenCodeSession(id: id, title: "Session", workspaceID: nil, directory: directory, projectID: nil, parentID: nil)
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
