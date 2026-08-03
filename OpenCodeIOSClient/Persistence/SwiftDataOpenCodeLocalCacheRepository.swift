import Foundation
import SwiftData

@Model
final class OpenCodeCachedProjectsRecord {
    @Attribute(.unique) var key: String
    var serverID: String
    var payload: Data
    var refreshedAt: Date
    var writtenAt: Date = Date.distantPast

    init(key: String, serverID: String, payload: Data, refreshedAt: Date, writtenAt: Date) {
        self.key = key
        self.serverID = serverID
        self.payload = payload
        self.refreshedAt = refreshedAt
        self.writtenAt = writtenAt
    }
}

@Model
final class OpenCodeCachedDirectorySessionsRecord {
    @Attribute(.unique) var key: String
    var serverID: String
    var payload: Data
    var refreshedAt: Date
    var writtenAt: Date = Date.distantPast

    init(key: String, serverID: String, payload: Data, refreshedAt: Date, writtenAt: Date) {
        self.key = key
        self.serverID = serverID
        self.payload = payload
        self.refreshedAt = refreshedAt
        self.writtenAt = writtenAt
    }
}

@Model
final class OpenCodeCachedChatRecord {
    @Attribute(.unique) var key: String
    var serverID: String
    var sessionID: String
    var messagesPayload: Data?
    var todosPayload: Data?
    var messagesRefreshedAt: Date?
    var todosRefreshedAt: Date?
    var messagesWrittenAt: Date = Date.distantPast
    var todosWrittenAt: Date = Date.distantPast
    var deletedAt: Date?

    init(
        key: String,
        serverID: String,
        sessionID: String,
        messagesPayload: Data? = nil,
        todosPayload: Data? = nil,
        messagesRefreshedAt: Date? = nil,
        todosRefreshedAt: Date? = nil,
        messagesWrittenAt: Date = .distantPast,
        todosWrittenAt: Date = .distantPast,
        deletedAt: Date? = nil
    ) {
        self.key = key
        self.serverID = serverID
        self.sessionID = sessionID
        self.messagesPayload = messagesPayload
        self.todosPayload = todosPayload
        self.messagesRefreshedAt = messagesRefreshedAt
        self.todosRefreshedAt = todosRefreshedAt
        self.messagesWrittenAt = messagesWrittenAt
        self.todosWrittenAt = todosWrittenAt
        self.deletedAt = deletedAt
    }
}

enum OpenCodeLocalCacheSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            OpenCodeCachedProjectsRecord.self,
            OpenCodeCachedDirectorySessionsRecord.self,
            OpenCodeCachedChatRecord.self,
        ]
    }
}

enum OpenCodeLocalCacheMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OpenCodeLocalCacheSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

@ModelActor
actor SwiftDataOpenCodeLocalCacheRepository: OpenCodeLocalCacheRepository {
    func loadProjects(serverID: String) async throws -> OpenCodeCachedProjectsSnapshot? {
        let key = OpenCodeLocalCacheKey.make([serverID])
        guard let record = try projectsRecord(forKey: key) else { return nil }
        return OpenCodeCachedProjectsSnapshot(
            projects: try decode([OpenCodeProject].self, from: record.payload),
            refreshedAt: record.refreshedAt
        )
    }

    func saveProjects(
        _ projects: [OpenCodeProject],
        serverID: String,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {
        let key = OpenCodeLocalCacheKey.make([serverID])
        let payload = try encode(projects)
        if let record = try projectsRecord(forKey: key) {
            guard writtenAt >= record.writtenAt else { return }
            record.serverID = serverID
            record.payload = payload
            record.refreshedAt = refreshedAt
            record.writtenAt = writtenAt
        } else {
            modelContext.insert(
                OpenCodeCachedProjectsRecord(
                    key: key,
                    serverID: serverID,
                    payload: payload,
                    refreshedAt: refreshedAt,
                    writtenAt: writtenAt
                )
            )
        }
        try modelContext.save()
    }

    func loadDirectorySessions(
        serverID: String,
        directory: String?
    ) async throws -> OpenCodeCachedDirectorySessionsSnapshot? {
        let key = OpenCodeLocalCacheKey.make([serverID, directory])
        guard let record = try directorySessionsRecord(forKey: key) else { return nil }
        return OpenCodeCachedDirectorySessionsSnapshot(
            sessions: try decode([OpenCodeSession].self, from: record.payload),
            refreshedAt: record.refreshedAt
        )
    }

    func saveDirectorySessions(
        _ sessions: [OpenCodeSession],
        serverID: String,
        directory: String?,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {
        let key = OpenCodeLocalCacheKey.make([serverID, directory])
        let payload = try encode(sessions)
        if let record = try directorySessionsRecord(forKey: key) {
            guard writtenAt >= record.writtenAt else { return }
            record.serverID = serverID
            record.payload = payload
            record.refreshedAt = refreshedAt
            record.writtenAt = writtenAt
        } else {
            modelContext.insert(
                OpenCodeCachedDirectorySessionsRecord(
                    key: key,
                    serverID: serverID,
                    payload: payload,
                    refreshedAt: refreshedAt,
                    writtenAt: writtenAt
                )
            )
        }
        try modelContext.save()
    }

    func loadChat(
        serverID: String,
        sessionID: String
    ) async throws -> OpenCodeCachedChatSnapshot? {
        let key = OpenCodeLocalCacheKey.make([serverID, sessionID])
        guard let record = try chatRecord(forKey: key) else { return nil }
        guard record.deletedAt == nil else { return nil }

        let messages = record.messagesPayload
            .flatMap { try? decode([OpenCodeMessageEnvelope].self, from: $0) }
        let todos = record.todosPayload
            .flatMap { try? decode([OpenCodeTodo].self, from: $0) }

        return OpenCodeCachedChatSnapshot(
            preparedMessages: OpenCodeCachedMessageState(
                envelopes: messages ?? [],
                sessionID: sessionID
            ),
            todos: todos ?? [],
            messagesRefreshedAt: messages == nil ? nil : record.messagesRefreshedAt,
            todosRefreshedAt: todos == nil ? nil : record.todosRefreshedAt
        )
    }

    func saveChatMessages(
        _ messages: [OpenCodeMessageEnvelope],
        serverID: String,
        sessionID: String,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {
        let key = OpenCodeLocalCacheKey.make([serverID, sessionID])
        let payload = try encode(messages)
        if let record = try chatRecord(forKey: key) {
            guard writtenAt >= record.messagesWrittenAt,
                  record.deletedAt.map({ writtenAt > $0 }) ?? true else { return }
            record.serverID = serverID
            record.sessionID = sessionID
            record.messagesPayload = payload
            record.messagesRefreshedAt = refreshedAt
            record.messagesWrittenAt = writtenAt
            record.deletedAt = nil
        } else {
            modelContext.insert(
                OpenCodeCachedChatRecord(
                    key: key,
                    serverID: serverID,
                    sessionID: sessionID,
                    messagesPayload: payload,
                    messagesRefreshedAt: refreshedAt,
                    messagesWrittenAt: writtenAt
                )
            )
        }
        try modelContext.save()
    }

    func saveTodos(
        _ todos: [OpenCodeTodo],
        serverID: String,
        sessionID: String,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {
        let key = OpenCodeLocalCacheKey.make([serverID, sessionID])
        let payload = try encode(todos)
        if let record = try chatRecord(forKey: key) {
            guard writtenAt >= record.todosWrittenAt,
                  record.deletedAt.map({ writtenAt > $0 }) ?? true else { return }
            record.serverID = serverID
            record.sessionID = sessionID
            record.todosPayload = payload
            record.todosRefreshedAt = refreshedAt
            record.todosWrittenAt = writtenAt
            record.deletedAt = nil
        } else {
            modelContext.insert(
                OpenCodeCachedChatRecord(
                    key: key,
                    serverID: serverID,
                    sessionID: sessionID,
                    todosPayload: payload,
                    todosRefreshedAt: refreshedAt,
                    todosWrittenAt: writtenAt
                )
            )
        }
        try modelContext.save()
    }

    func removeSession(serverID: String, sessionID: String, removedAt: Date) async throws {
        for record in try directorySessionRecords(serverID: serverID) {
            guard removedAt >= record.writtenAt else { continue }
            let sessions = try decode([OpenCodeSession].self, from: record.payload)
            let remaining = sessions.filter { $0.id != sessionID }
            if remaining.count != sessions.count {
                record.payload = try encode(remaining)
            }
            record.writtenAt = removedAt
        }

        let chatKey = OpenCodeLocalCacheKey.make([serverID, sessionID])
        if let record = try chatRecord(forKey: chatKey) {
            if record.deletedAt.map({ removedAt >= $0 }) ?? true {
                record.messagesPayload = nil
                record.todosPayload = nil
                record.messagesRefreshedAt = nil
                record.todosRefreshedAt = nil
                record.messagesWrittenAt = removedAt
                record.todosWrittenAt = removedAt
                record.deletedAt = removedAt
            }
        } else {
            modelContext.insert(
                OpenCodeCachedChatRecord(
                    key: chatKey,
                    serverID: serverID,
                    sessionID: sessionID,
                    messagesWrittenAt: removedAt,
                    todosWrittenAt: removedAt,
                    deletedAt: removedAt
                )
            )
        }
        try modelContext.save()
    }

    func clear(serverID: String) async throws {
        for record in try projectRecords(serverID: serverID) {
            modelContext.delete(record)
        }
        for record in try directorySessionRecords(serverID: serverID) {
            modelContext.delete(record)
        }
        for record in try chatRecords(serverID: serverID) {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    private func projectsRecord(forKey key: String) throws -> OpenCodeCachedProjectsRecord? {
        let targetKey = key
        var descriptor = FetchDescriptor<OpenCodeCachedProjectsRecord>(
            predicate: #Predicate { $0.key == targetKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func directorySessionsRecord(forKey key: String) throws -> OpenCodeCachedDirectorySessionsRecord? {
        let targetKey = key
        var descriptor = FetchDescriptor<OpenCodeCachedDirectorySessionsRecord>(
            predicate: #Predicate { $0.key == targetKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func chatRecord(forKey key: String) throws -> OpenCodeCachedChatRecord? {
        let targetKey = key
        var descriptor = FetchDescriptor<OpenCodeCachedChatRecord>(
            predicate: #Predicate { $0.key == targetKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func projectRecords(serverID: String) throws -> [OpenCodeCachedProjectsRecord] {
        let targetServerID = serverID
        let descriptor = FetchDescriptor<OpenCodeCachedProjectsRecord>(
            predicate: #Predicate { $0.serverID == targetServerID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func directorySessionRecords(serverID: String) throws -> [OpenCodeCachedDirectorySessionsRecord] {
        let targetServerID = serverID
        let descriptor = FetchDescriptor<OpenCodeCachedDirectorySessionsRecord>(
            predicate: #Predicate { $0.serverID == targetServerID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func chatRecords(serverID: String) throws -> [OpenCodeCachedChatRecord] {
        let targetServerID = serverID
        let descriptor = FetchDescriptor<OpenCodeCachedChatRecord>(
            predicate: #Predicate { $0.serverID == targetServerID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}

struct NoOpOpenCodeLocalCacheRepository: OpenCodeLocalCacheRepository {
    func loadProjects(serverID: String) async throws -> OpenCodeCachedProjectsSnapshot? { nil }

    func saveProjects(
        _ projects: [OpenCodeProject],
        serverID: String,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {}

    func loadDirectorySessions(
        serverID: String,
        directory: String?
    ) async throws -> OpenCodeCachedDirectorySessionsSnapshot? { nil }

    func saveDirectorySessions(
        _ sessions: [OpenCodeSession],
        serverID: String,
        directory: String?,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {}

    func loadChat(
        serverID: String,
        sessionID: String
    ) async throws -> OpenCodeCachedChatSnapshot? { nil }

    func saveChatMessages(
        _ messages: [OpenCodeMessageEnvelope],
        serverID: String,
        sessionID: String,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {}

    func saveTodos(
        _ todos: [OpenCodeTodo],
        serverID: String,
        sessionID: String,
        refreshedAt: Date,
        writtenAt: Date
    ) async throws {}

    func removeSession(serverID: String, sessionID: String, removedAt: Date) async throws {}

    func clear(serverID: String) async throws {}
}

enum OpenCodeLocalCacheRepositoryFactory {
    static func makeDefault() -> any OpenCodeLocalCacheRepository {
        do {
            return SwiftDataOpenCodeLocalCacheRepository(
                modelContainer: try makeContainer(isStoredInMemoryOnly: false)
            )
        } catch {
            return NoOpOpenCodeLocalCacheRepository()
        }
    }

    static func makeInMemory() throws -> any OpenCodeLocalCacheRepository {
        SwiftDataOpenCodeLocalCacheRepository(
            modelContainer: try makeContainer(isStoredInMemoryOnly: true)
        )
    }

    private static func makeContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: OpenCodeLocalCacheSchemaV1.self)
        // Keep this experimental cache app-private and disconnected from CloudKit.
        let configuration = ModelConfiguration(
            "OpenCodeLocalSnapshotCache",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: OpenCodeLocalCacheMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

private enum OpenCodeLocalCacheKey {
    /// Nil and strings use distinct tags; string lengths are measured in UTF-8 bytes.
    static func make(_ components: [String?]) -> String {
        components.map { component in
            guard let component else { return "n" }
            return "s\(component.utf8.count):\(component)"
        }.joined()
    }
}
