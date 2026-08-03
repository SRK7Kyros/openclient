import XCTest
@testable import OpenClient

final class OpenCodeLocalCacheRepositoryTests: XCTestCase {
    func testStreamDeltasWaitForCanonicalEventBeforeWritingChatSnapshot() {
        XCTAssertFalse(OpenCodeLocalCacheEventWritePolicy.writesChatSnapshot(for: .messagePartDelta(
            sessionID: "ses_cache",
            messageID: "msg_cache",
            partID: "prt_cache",
            field: "text",
            delta: "Streaming"
        )))
        XCTAssertTrue(OpenCodeLocalCacheEventWritePolicy.writesChatSnapshot(for: .messagePartUpdated(
            OpenCodePart(
                id: "prt_cache",
                messageID: "msg_cache",
                sessionID: "ses_cache",
                type: "text",
                mime: nil,
                filename: nil,
                url: nil,
                reason: nil,
                tool: nil,
                callID: nil,
                state: nil,
                text: "Complete"
            )
        )))
        XCTAssertTrue(OpenCodeLocalCacheEventWritePolicy.writesChatSnapshot(for: .sessionIdle(sessionID: "ses_cache")))
    }

    func testRoundTripPreservesSnapshotValuesAndRefreshDates() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let projectsDate = Date(timeIntervalSince1970: 1_000)
        let sessionsDate = Date(timeIntervalSince1970: 2_000)
        let messagesDate = Date(timeIntervalSince1970: 3_000)
        let todosDate = Date(timeIntervalSince1970: 4_000)
        let projects = [project(id: "project-1", name: "Project One")]
        let sessions = [session(id: "session-1", title: "Session One", directory: "/project")]
        let messages = [message(id: "message-1", sessionID: "session-1", text: "Hello")]
        let todos = [OpenCodeTodo(content: "Cache snapshots", status: "pending", priority: "high")]

        try await repository.saveProjects(projects, serverID: "server", refreshedAt: projectsDate)
        try await repository.saveDirectorySessions(
            sessions,
            serverID: "server",
            directory: "/project",
            refreshedAt: sessionsDate
        )
        try await repository.saveChatMessages(
            messages,
            serverID: "server",
            sessionID: "session-1",
            refreshedAt: messagesDate
        )
        try await repository.saveTodos(
            todos,
            serverID: "server",
            sessionID: "session-1",
            refreshedAt: todosDate
        )

        let projectsSnapshot = try await repository.loadProjects(serverID: "server")
        let sessionsSnapshot = try await repository.loadDirectorySessions(
            serverID: "server",
            directory: "/project"
        )
        let chatSnapshot = try await repository.loadChat(serverID: "server", sessionID: "session-1")
        let loadedProjects = try XCTUnwrap(projectsSnapshot)
        let loadedSessions = try XCTUnwrap(sessionsSnapshot)
        let loadedChat = try XCTUnwrap(chatSnapshot)

        XCTAssertEqual(loadedProjects.projects, projects)
        XCTAssertEqual(loadedProjects.refreshedAt, projectsDate)
        XCTAssertEqual(loadedSessions.sessions, sessions)
        XCTAssertEqual(loadedSessions.refreshedAt, sessionsDate)
        XCTAssertEqual(loadedChat.messages, messages)
        XCTAssertEqual(loadedChat.todos, todos)
        XCTAssertEqual(loadedChat.messagesRefreshedAt, messagesDate)
        XCTAssertEqual(loadedChat.todosRefreshedAt, todosDate)
    }

    func testGlobalAndLiteralGlobalDirectoryScopesDoNotCollide() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let globalSessions = [session(id: "global-session", title: "Global", directory: nil)]
        let literalGlobalSessions = [session(id: "literal-session", title: "Literal", directory: "global")]

        try await repository.saveDirectorySessions(
            globalSessions,
            serverID: "server",
            directory: nil,
            refreshedAt: Date(timeIntervalSince1970: 1)
        )
        try await repository.saveDirectorySessions(
            literalGlobalSessions,
            serverID: "server",
            directory: "global",
            refreshedAt: Date(timeIntervalSince1970: 2)
        )

        let global = try await repository.loadDirectorySessions(serverID: "server", directory: nil)
        let literalGlobal = try await repository.loadDirectorySessions(serverID: "server", directory: "global")

        XCTAssertEqual(global?.sessions, globalSessions)
        XCTAssertEqual(literalGlobal?.sessions, literalGlobalSessions)
    }

    func testSameSessionAndMessageIDsRemainIsolatedAcrossServers() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let sessionA = session(id: "shared-session", title: "Server A", directory: nil)
        let sessionB = session(id: "shared-session", title: "Server B", directory: nil)
        let messageA = message(id: "shared-message", sessionID: sessionA.id, text: "A")
        let messageB = message(id: "shared-message", sessionID: sessionB.id, text: "B")

        try await repository.saveDirectorySessions(
            [sessionA],
            serverID: "server-a",
            directory: nil,
            refreshedAt: Date()
        )
        try await repository.saveDirectorySessions(
            [sessionB],
            serverID: "server-b",
            directory: nil,
            refreshedAt: Date()
        )
        try await repository.saveChatMessages(
            [messageA],
            serverID: "server-a",
            sessionID: sessionA.id,
            refreshedAt: Date()
        )
        try await repository.saveChatMessages(
            [messageB],
            serverID: "server-b",
            sessionID: sessionB.id,
            refreshedAt: Date()
        )

        let sessionsA = try await repository.loadDirectorySessions(serverID: "server-a", directory: nil)
        let sessionsB = try await repository.loadDirectorySessions(serverID: "server-b", directory: nil)
        let chatA = try await repository.loadChat(serverID: "server-a", sessionID: sessionA.id)
        let chatB = try await repository.loadChat(serverID: "server-b", sessionID: sessionB.id)

        XCTAssertEqual(sessionsA?.sessions, [sessionA])
        XCTAssertEqual(sessionsB?.sessions, [sessionB])
        XCTAssertEqual(chatA?.messages, [messageA])
        XCTAssertEqual(chatB?.messages, [messageB])
    }

    func testTodoDuplicatesAndOrderArePreserved() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let todos = [
            OpenCodeTodo(content: "Repeated", status: "pending", priority: "high"),
            OpenCodeTodo(content: "Repeated", status: "completed", priority: "low"),
            OpenCodeTodo(content: "Last", status: "in_progress", priority: "medium"),
        ]

        try await repository.saveTodos(
            todos,
            serverID: "server",
            sessionID: "session",
            refreshedAt: Date()
        )

        let chat = try await repository.loadChat(serverID: "server", sessionID: "session")
        XCTAssertEqual(chat?.todos, todos)
    }

    func testLoadedChatPreparesOnlyTheLatestUserRoundForImmediatePresentation() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let messages = [
            message(id: "msg-01", sessionID: "session", role: "user", text: "First"),
            message(id: "msg-02", sessionID: "session", text: "First answer"),
            message(id: "msg-03", sessionID: "session", role: "user", text: "Second"),
            message(id: "msg-04", sessionID: "session", text: "Second answer"),
            message(id: "msg-05", sessionID: "session", text: "More work"),
        ]

        try await repository.saveChatMessages(
            messages,
            serverID: "server",
            sessionID: "session",
            refreshedAt: Date()
        )

        let loadedSnapshot = try await repository.loadChat(serverID: "server", sessionID: "session")
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.preparedMessages.messages.map(\.id), messages.map(\.id))
        XCTAssertEqual(
            snapshot.preparedMessages.immediateMessages.map(\.id),
            ["msg-03", "msg-04", "msg-05"]
        )
    }

    func testRemoveSessionRemovesItFromAllScopesAndDeletesOnlyItsChat() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let removed = session(id: "removed", title: "Removed", directory: nil)
        let retained = session(id: "retained", title: "Retained", directory: "/project")

        try await repository.saveDirectorySessions(
            [removed],
            serverID: "server",
            directory: nil,
            refreshedAt: Date()
        )
        try await repository.saveDirectorySessions(
            [removed, retained],
            serverID: "server",
            directory: "/project",
            refreshedAt: Date()
        )
        try await repository.saveChatMessages(
            [message(id: "removed-message", sessionID: removed.id, text: "Remove")],
            serverID: "server",
            sessionID: removed.id,
            refreshedAt: Date()
        )
        try await repository.saveChatMessages(
            [message(id: "retained-message", sessionID: retained.id, text: "Keep")],
            serverID: "server",
            sessionID: retained.id,
            refreshedAt: Date()
        )

        try await repository.removeSession(serverID: "server", sessionID: removed.id)

        let global = try await repository.loadDirectorySessions(serverID: "server", directory: nil)
        let project = try await repository.loadDirectorySessions(serverID: "server", directory: "/project")
        let removedChat = try await repository.loadChat(serverID: "server", sessionID: removed.id)
        let retainedChat = try await repository.loadChat(serverID: "server", sessionID: retained.id)

        XCTAssertEqual(global?.sessions, [])
        XCTAssertEqual(project?.sessions, [retained])
        XCTAssertNil(removedChat)
        XCTAssertEqual(retainedChat?.messages.map(\.id), ["retained-message"])
    }

    func testSnapshotFreshnessRejectsStaleDates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = OpenCodeCachedProjectsSnapshot(
            projects: [],
            refreshedAt: now.addingTimeInterval(-OpenCodeLocalCacheFreshness.initialMaxAge - 1)
        )

        XCTAssertFalse(snapshot.isFresh(at: now))
        XCTAssertTrue(
            OpenCodeLocalCacheFreshness.isFresh(
                now.addingTimeInterval(-OpenCodeLocalCacheFreshness.initialMaxAge),
                at: now
            )
        )
        XCTAssertFalse(OpenCodeLocalCacheFreshness.isFresh(nil, at: now))
        XCTAssertFalse(OpenCodeLocalCacheFreshness.isFresh(now.addingTimeInterval(1), at: now))
    }

    func testOlderWriteCannotOverwriteNewerSnapshot() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let older = [session(id: "older", title: "Older", directory: nil)]
        let newer = [session(id: "newer", title: "Newer", directory: nil)]

        try await repository.saveDirectorySessions(
            newer,
            serverID: "server",
            directory: nil,
            refreshedAt: Date(timeIntervalSince1970: 20),
            writtenAt: Date(timeIntervalSince1970: 20)
        )
        try await repository.saveDirectorySessions(
            older,
            serverID: "server",
            directory: nil,
            refreshedAt: Date(timeIntervalSince1970: 10),
            writtenAt: Date(timeIntervalSince1970: 10)
        )

        let snapshot = try await repository.loadDirectorySessions(serverID: "server", directory: nil)
        XCTAssertEqual(snapshot?.sessions, newer)
    }

    func testDelayedChatWriteCannotResurrectRemovedSession() async throws {
        let repository = try OpenCodeLocalCacheRepositoryFactory.makeInMemory()
        let cachedMessage = message(id: "message", sessionID: "session", text: "Cached")

        try await repository.removeSession(
            serverID: "server",
            sessionID: "session",
            removedAt: Date(timeIntervalSince1970: 20)
        )
        try await repository.saveChatMessages(
            [cachedMessage],
            serverID: "server",
            sessionID: "session",
            refreshedAt: Date(timeIntervalSince1970: 10),
            writtenAt: Date(timeIntervalSince1970: 10)
        )

        let chat = try await repository.loadChat(serverID: "server", sessionID: "session")
        XCTAssertNil(chat)
    }

    private func project(id: String, name: String) -> OpenCodeProject {
        OpenCodeProject(
            id: id,
            worktree: "/\(id)",
            vcs: "git",
            name: name,
            sandboxes: nil,
            icon: nil,
            time: nil
        )
    }

    private func session(id: String, title: String, directory: String?) -> OpenCodeSession {
        OpenCodeSession(
            id: id,
            title: title,
            workspaceID: nil,
            directory: directory,
            projectID: nil,
            parentID: nil
        )
    }

    private func message(
        id: String,
        sessionID: String,
        role: String = "assistant",
        text: String
    ) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: OpenCodeMessage(
                id: id,
                role: role,
                sessionID: sessionID,
                time: nil,
                agent: nil,
                model: nil
            ),
            parts: [
                OpenCodePart(
                    id: "part-\(id)",
                    messageID: id,
                    sessionID: sessionID,
                    type: "text",
                    mime: nil,
                    filename: nil,
                    url: nil,
                    reason: nil,
                    tool: nil,
                    callID: nil,
                    state: nil,
                    text: text
                )
            ]
        )
    }
}
