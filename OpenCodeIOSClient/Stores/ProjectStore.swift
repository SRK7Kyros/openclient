import Combine
import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    static let listPreferencesStorageKey = "opencode.projectListPreferences.v1"

    @Published var projects: [OpenCodeProject]
    @Published var currentProject: OpenCodeProject?
    @Published var selectedDirectory: String?
    @Published var selectedContentTab: OpenClientProjectContentTab
    @Published var isShowingProjectPicker: Bool
    @Published var searchQuery: String
    @Published var searchResults: [String]
    @Published var isShowingCreateProjectSheet: Bool
    @Published var createProjectQuery: String
    @Published var createProjectResults: [String]
    @Published var createProjectSelectedDirectory: String?
    @Published private var listPreferencesByScope: [String: ListPreferences]

    private let userDefaults: UserDefaults

    init(
        projects: [OpenCodeProject] = [],
        currentProject: OpenCodeProject? = nil,
        selectedDirectory: String? = nil,
        selectedContentTab: OpenClientProjectContentTab = .sessions,
        isShowingProjectPicker: Bool = false,
        searchQuery: String = "",
        searchResults: [String] = [],
        isShowingCreateProjectSheet: Bool = false,
        createProjectQuery: String = "",
        createProjectResults: [String] = [],
        createProjectSelectedDirectory: String? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.projects = projects
        self.currentProject = currentProject
        self.selectedDirectory = selectedDirectory
        self.selectedContentTab = selectedContentTab
        self.isShowingProjectPicker = isShowingProjectPicker
        self.searchQuery = searchQuery
        self.searchResults = searchResults
        self.isShowingCreateProjectSheet = isShowingCreateProjectSheet
        self.createProjectQuery = createProjectQuery
        self.createProjectResults = createProjectResults
        self.createProjectSelectedDirectory = createProjectSelectedDirectory
        self.userDefaults = userDefaults
        self.listPreferencesByScope = Self.loadListPreferences(userDefaults: userDefaults)
    }

    func orderedProjects(scopeKey: String) -> [OpenCodeProject] {
        let projectsByID = projects.reduce(into: [String: OpenCodeProject]()) { result, project in
            result[project.id] = project
        }
        let preferredOrder = listPreferencesByScope[scopeKey]?.orderedIDs ?? []
        var seen = Set<String>()
        var ordered = preferredOrder.compactMap { id -> OpenCodeProject? in
            guard seen.insert(id).inserted else { return nil }
            return projectsByID[id]
        }
        ordered.append(contentsOf: projects.filter { seen.insert($0.id).inserted })
        return ordered
    }

    func visibleProjects(scopeKey: String) -> [OpenCodeProject] {
        orderedProjects(scopeKey: scopeKey).filter { isProjectVisible($0, scopeKey: scopeKey) }
    }

    func isProjectVisible(_ project: OpenCodeProject, scopeKey: String) -> Bool {
        listPreferencesByScope[scopeKey]?.hiddenIDs.contains(project.id) != true
    }

    func setProjectVisibility(_ project: OpenCodeProject, isVisible: Bool, scopeKey: String) {
        var preferences = listPreferencesByScope[scopeKey] ?? ListPreferences()
        if isVisible {
            preferences.hiddenIDs.remove(project.id)
        } else {
            preferences.hiddenIDs.insert(project.id)
        }
        setListPreferences(preferences, scopeKey: scopeKey)
    }

    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int, scopeKey: String) {
        var orderedIDs = orderedProjects(scopeKey: scopeKey).map(\.id)
        let validOffsets = source.filter { orderedIDs.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }

        let movingIDs = validOffsets.map { orderedIDs[$0] }
        for offset in validOffsets.reversed() {
            orderedIDs.remove(at: offset)
        }
        let removedBeforeDestination = validOffsets.lazy.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), orderedIDs.count)
        orderedIDs.insert(contentsOf: movingIDs, at: insertionIndex)

        var preferences = listPreferencesByScope[scopeKey] ?? ListPreferences()
        let unavailableIDs = preferences.orderedIDs.filter { !orderedIDs.contains($0) }
        preferences.orderedIDs = orderedIDs + unavailableIDs
        setListPreferences(preferences, scopeKey: scopeKey)
    }

    private func setListPreferences(_ preferences: ListPreferences, scopeKey: String) {
        listPreferencesByScope[scopeKey] = preferences
        guard let data = try? JSONEncoder().encode(listPreferencesByScope) else { return }
        userDefaults.set(data, forKey: Self.listPreferencesStorageKey)
    }

    private static func loadListPreferences(userDefaults: UserDefaults) -> [String: ListPreferences] {
        guard let data = userDefaults.data(forKey: listPreferencesStorageKey),
              let preferences = try? JSONDecoder().decode([String: ListPreferences].self, from: data) else {
            return [:]
        }
        return preferences
    }
}

private struct ListPreferences: Codable {
    var orderedIDs: [String] = []
    var hiddenIDs: Set<String> = []
}
