import Combine
import Foundation

@MainActor
final class ProjectPreferencesStore: ObservableObject {
    @Published var liveActivityAutoStartByScope: [String: Bool]
    @Published var projectWorkspacesEnabledByScope: [String: Bool]
    @Published var projectActionsByScope: [String: [OpenCodeAction]]
    @Published var showsRecentSessionsInProjectList: Bool

    init(
        liveActivityAutoStartByScope: [String: Bool] = [:],
        projectWorkspacesEnabledByScope: [String: Bool] = [:],
        projectActionsByScope: [String: [OpenCodeAction]] = [:],
        showsRecentSessionsInProjectList: Bool = true
    ) {
        self.liveActivityAutoStartByScope = liveActivityAutoStartByScope
        self.projectWorkspacesEnabledByScope = projectWorkspacesEnabledByScope
        self.projectActionsByScope = projectActionsByScope
        self.showsRecentSessionsInProjectList = showsRecentSessionsInProjectList
    }
}

struct ProjectListPreferences: Codable, Equatable {
    var showsRecentSessions = true
}

struct ServerScopedProjectListPreferences: Codable, Equatable {
    var preferencesByBaseURL: [String: ProjectListPreferences] = [:]
}

enum ProjectListPreferencesStore {
    private static let storageKey = "projectListPreferences"

    static func load() -> ServerScopedProjectListPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode(ServerScopedProjectListPreferences.self, from: data) else {
            return ServerScopedProjectListPreferences()
        }

        return preferences
    }

    static func save(_ preferences: ServerScopedProjectListPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
