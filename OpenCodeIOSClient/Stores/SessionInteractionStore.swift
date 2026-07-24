import Combine
import Foundation

@MainActor
final class SessionInteractionStore: ObservableObject {
    @Published var todos: [OpenCodeTodo]
    @Published var permissions: [OpenCodePermission]
    @Published var questions: [OpenCodeQuestionRequest]

    init(
        todos: [OpenCodeTodo] = [],
        permissions: [OpenCodePermission] = [],
        questions: [OpenCodeQuestionRequest] = []
    ) {
        self.todos = todos
        self.permissions = permissions
        self.questions = questions
    }

    func reset() {
        todos = []
        permissions = []
        questions = []
    }

    func replaceTodos(_ nextTodos: [OpenCodeTodo]) {
        todos = nextTodos
    }

    func replacePermissions(_ nextPermissions: [OpenCodePermission]) {
        permissions = nextPermissions
    }

    func replaceQuestions(_ nextQuestions: [OpenCodeQuestionRequest]) {
        questions = nextQuestions
    }

    func applyDirectoryBootstrap(_ bootstrap: OpenCodeDirectoryBootstrap) {
        permissions = bootstrap.permissions
        questions = bootstrap.questions
    }

    func applySelectedSession(
        sessionID: String,
        sessions: [OpenCodeSession],
        syncState: OpenCodeDirectorySyncState
    ) {
        todos = syncState.todosBySessionID[sessionID] ?? []
        permissions = Self.permissions(
            forSessionTreeRootID: sessionID,
            sessions: sessions,
            permissionsBySessionID: syncState.permissionsBySessionID
        )
        questions = Self.questions(
            forSessionTreeRootID: sessionID,
            sessions: sessions,
            questionsBySessionID: syncState.questionsBySessionID
        )
    }

    func applyTodos(_ nextTodos: [OpenCodeTodo], forSessionID sessionID: String, selectedSessionID: String?) {
        guard selectedSessionID == sessionID else { return }
        todos = nextTodos
    }

    func applyLoadedPermissions(_ nextPermissions: [OpenCodePermission]) {
        permissions = nextPermissions
    }

    func applyLoadedQuestions(_ nextQuestions: [OpenCodeQuestionRequest]) {
        questions = nextQuestions
    }

    @discardableResult
    func applyVisibleInteractions(
        todos nextTodos: [OpenCodeTodo],
        permissions nextPermissions: [OpenCodePermission],
        questions nextQuestions: [OpenCodeQuestionRequest]
    ) -> Bool {
        var changed = false
        if todos != nextTodos {
            todos = nextTodos
            changed = true
        }
        if permissions != nextPermissions {
            permissions = nextPermissions
            changed = true
        }
        if questions != nextQuestions {
            questions = nextQuestions
            changed = true
        }
        return changed
    }

    func permissions(forSessionTreeRootID sessionID: String, sessions: [OpenCodeSession]) -> [OpenCodePermission] {
        Self.requests(
            forSessionTreeRootID: sessionID,
            sessions: sessions,
            requestsBySessionID: Dictionary(grouping: permissions, by: \.sessionID)
        )
    }

    func questions(forSessionTreeRootID sessionID: String, sessions: [OpenCodeSession]) -> [OpenCodeQuestionRequest] {
        Self.requests(
            forSessionTreeRootID: sessionID,
            sessions: sessions,
            requestsBySessionID: Dictionary(grouping: questions, by: \.sessionID)
        )
    }

    func hasPermissionRequest(forSessionTreeRootID sessionID: String, sessions: [OpenCodeSession]) -> Bool {
        !permissions(forSessionTreeRootID: sessionID, sessions: sessions).isEmpty
    }

    func removePermission(id: String) {
        permissions.removeAll { $0.id == id }
    }

    func removeQuestion(id: String) {
        questions.removeAll { $0.id == id }
    }

    static func permissions(
        forSessionTreeRootID sessionID: String,
        sessions: [OpenCodeSession],
        permissionsBySessionID: [String: [OpenCodePermission]]
    ) -> [OpenCodePermission] {
        requests(
            forSessionTreeRootID: sessionID,
            sessions: sessions,
            requestsBySessionID: permissionsBySessionID
        )
    }

    static func questions(
        forSessionTreeRootID sessionID: String,
        sessions: [OpenCodeSession],
        questionsBySessionID: [String: [OpenCodeQuestionRequest]]
    ) -> [OpenCodeQuestionRequest] {
        requests(
            forSessionTreeRootID: sessionID,
            sessions: sessions,
            requestsBySessionID: questionsBySessionID
        )
    }

    private static func requests<Request>(
        forSessionTreeRootID sessionID: String,
        sessions: [OpenCodeSession],
        requestsBySessionID: [String: [Request]]
    ) -> [Request] {
        let childrenByParentID = Dictionary(grouping: sessions.compactMap { session -> (String, String)? in
            session.parentID.map { ($0, session.id) }
        }, by: \.0)
        var seen = Set([sessionID])
        var sessionIDs = [sessionID]
        var index = 0

        while index < sessionIDs.count {
            let currentID = sessionIDs[index]
            index += 1
            for child in childrenByParentID[currentID] ?? [] where seen.insert(child.1).inserted {
                sessionIDs.append(child.1)
            }
        }

        return sessionIDs.flatMap { requestsBySessionID[$0] ?? [] }
    }
}
