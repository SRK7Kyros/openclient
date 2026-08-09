import Foundation

struct OpenCodeGlobalBootstrap {
    let health: HealthResponse
    let projects: [OpenCodeProject]
    let currentProject: OpenCodeProject?
}

struct OpenCodeDirectoryBootstrap {
    let sessions: [OpenCodeSession]
    let sessionTotal: Int
    let sessionLimit: Int
    let commands: [OpenCodeCommand]
    let permissions: [OpenCodePermission]
    let questions: [OpenCodeQuestionRequest]
}

enum OpenCodeBootstrap {
    static func bootstrapGlobal(client: OpenCodeAPIClient) async throws -> OpenCodeGlobalBootstrap {
        async let health = client.health()
        async let projects = client.listProjects()
        async let currentProject = try? client.currentProject()

        return try await OpenCodeGlobalBootstrap(
            health: health,
            projects: projects,
            currentProject: currentProject
        )
    }

    static func bootstrapDirectory(
        client: OpenCodeAPIClient,
        directory: String?,
        sessionLimit: Int
    ) async throws -> OpenCodeDirectoryBootstrap {
        async let sessions = client.listSessions(directory: directory, roots: true, limit: sessionLimit)
        async let commands = client.listCommands(directory: directory)
        async let permissions = client.listPermissions(directory: directory)
        async let questions = client.listQuestions(directory: directory)
        let loadedSessions = try await sessions

        return OpenCodeDirectoryBootstrap(
            sessions: loadedSessions,
            sessionTotal: loadedSessions.count < sessionLimit ? loadedSessions.count : loadedSessions.count + 1,
            sessionLimit: sessionLimit,
            commands: try await commands,
            permissions: try await permissions,
            questions: try await questions
        )
    }
}
