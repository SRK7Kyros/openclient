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

    func applySelectedSession(sessionID: String, syncState: OpenCodeDirectorySyncState) {
        todos = syncState.todosBySessionID[sessionID] ?? []
        permissions = syncState.permissionsBySessionID[sessionID] ?? []
        questions = syncState.questionsBySessionID[sessionID] ?? []
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

    func permissions(forSessionID sessionID: String) -> [OpenCodePermission] {
        permissions.filter { $0.sessionID == sessionID }
    }

    func questions(forSessionID sessionID: String) -> [OpenCodeQuestionRequest] {
        questions.filter { $0.sessionID == sessionID }
    }

    func hasPermissionRequest(forSessionID sessionID: String) -> Bool {
        permissions.contains { $0.sessionID == sessionID }
    }

    func removePermission(id: String) {
        permissions.removeAll { $0.id == id }
    }

    func removeQuestion(id: String) {
        questions.removeAll { $0.id == id }
    }
}
