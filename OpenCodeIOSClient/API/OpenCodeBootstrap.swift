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
        let loadedPermissions = try await permissions
        let loadedQuestions = try await questions
        let interactionSessions = await loadMissingSessions(
            sessionIDs: loadedPermissions.map(\.sessionID) + loadedQuestions.map(\.sessionID),
            knownSessions: loadedSessions,
            client: client,
            directory: directory
        )

        return OpenCodeDirectoryBootstrap(
            sessions: loadedSessions + interactionSessions,
            sessionTotal: loadedSessions.count < sessionLimit ? loadedSessions.count : loadedSessions.count + 1,
            sessionLimit: sessionLimit,
            commands: try await commands,
            permissions: loadedPermissions,
            questions: loadedQuestions
        )
    }

    static func loadMissingSessions(
        sessionIDs: [String],
        knownSessions: [OpenCodeSession],
        client: OpenCodeAPIClient,
        directory: String?,
        workspaceID: String? = nil
    ) async -> [OpenCodeSession] {
        var knownIDs = Set(knownSessions.map(\.id))
        var pendingIDs = Set(sessionIDs).subtracting(knownIDs)
        var loadedSessions: [OpenCodeSession] = []

        while !pendingIDs.isEmpty {
            let loaded = await withTaskGroup(of: OpenCodeSession?.self, returning: [OpenCodeSession].self) { group in
                for sessionID in pendingIDs {
                    group.addTask {
                        try? await client.getSession(
                            sessionID: sessionID,
                            directory: directory,
                            workspaceID: workspaceID
                        )
                    }
                }

                var sessions: [OpenCodeSession] = []
                for await session in group {
                    if let session {
                        sessions.append(session)
                    }
                }
                return sessions.sorted { $0.id < $1.id }
            }

            guard !loaded.isEmpty else { break }
            loadedSessions.append(contentsOf: loaded)
            knownIDs.formUnion(loaded.map(\.id))
            pendingIDs = Set(loaded.compactMap(\.parentID)).subtracting(knownIDs)
        }

        return loadedSessions
    }
}
