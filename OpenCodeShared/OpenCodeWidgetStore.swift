import Foundation

struct OpenCodeWidgetStore {
    static let appGroupIdentifier = "group.com.ntoporcov.openclient"

    private let storageKey = "OpenCodeWidgetSnapshotPayload"
    private let maxPayloadBytes = 1_000_000
    private let maxModelsPerServer = 120


    func load() -> OpenCodeWidgetSnapshotPayload {
        guard let data = defaults.data(forKey: storageKey),
              data.count <= maxPayloadBytes,
              let payload = try? JSONDecoder().decode(OpenCodeWidgetSnapshotPayload.self, from: data) else {
            return .empty
        }
        return payload
    }

    func save(_ payload: OpenCodeWidgetSnapshotPayload) {
        var payload = payload
        payload.models = limitedModelSnapshots(payload.models)
        guard var data = try? JSONEncoder().encode(payload) else { return }
        if data.count > maxPayloadBytes {
            payload.models = []
            guard let reducedData = try? JSONEncoder().encode(payload), reducedData.count <= maxPayloadBytes else { return }
            data = reducedData
        }
        defaults.set(data, forKey: storageKey)
    }

    func updatingServer(
        _ server: OpenCodeWidgetServerSnapshot,
        projects: [OpenCodeWidgetProjectSnapshot],
        sessions: [OpenCodeWidgetSessionSnapshot],
        replacingSessionIDs: Set<String>,
        commands: [OpenCodeWidgetCommandSnapshot] = [],
        replacingCommandProjectIDs: Set<String> = [],
        models: [OpenCodeWidgetModelSnapshot] = []
    ) {
        var payload = load()
        payload.servers.removeAll { $0.id == server.id }
        payload.servers = payload.servers.map { existing in
            OpenCodeWidgetServerSnapshot(
                id: existing.id,
                displayName: existing.displayName,
                baseURL: existing.baseURL,
                username: existing.username,
                generatedAt: existing.generatedAt,
                isLastConnected: false
            )
        }
        payload.servers.insert(server, at: 0)
        payload.projects.removeAll { $0.serverID == server.id }
        payload.projects.append(contentsOf: projects)
        payload.sessions.removeAll { $0.serverID == server.id && replacingSessionIDs.contains($0.id) }
        payload.sessions.append(contentsOf: sessions)
        if !replacingCommandProjectIDs.isEmpty {
            payload.commands.removeAll { command in
                command.serverID == server.id && replacingCommandProjectIDs.contains(command.projectID)
            }
            payload.commands.append(contentsOf: commands)
        }
        if !models.isEmpty {
            payload.models.removeAll { $0.serverID == server.id }
            payload.models.append(contentsOf: models)
        }
        payload.generatedAt = Date()
        save(payload)
    }

    private func limitedModelSnapshots(_ models: [OpenCodeWidgetModelSnapshot]) -> [OpenCodeWidgetModelSnapshot] {
        var countsByServerID: [String: Int] = [:]
        return models.filter { model in
            let count = countsByServerID[model.serverID, default: 0]
            guard count < maxModelsPerServer else { return false }
            countsByServerID[model.serverID] = count + 1
            return true
        }
    }

    func removeSession(serverID: String, sessionID: String) {
        var payload = load()
        payload.sessions.removeAll { $0.serverID == serverID && $0.id == sessionID }
        payload.generatedAt = Date()
        save(payload)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
    }
}
