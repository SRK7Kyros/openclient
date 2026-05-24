import Foundation

@MainActor
final class ProjectCoordinator {
    private struct DirectorySearchScope {
        let directory: String
        let path: String
        let isPathLike: Bool
    }

    struct CreateProjectSearchResult {
        let selectedDirectory: String?
        let results: [String]
    }

    struct ProjectRefreshResult {
        let projects: [OpenCodeProject]
        let currentProject: OpenCodeProject?
    }

    struct CreateProjectResult {
        let projects: [OpenCodeProject]?
        let selectedDirectory: String
    }

    struct ProjectSelectionResult {
        let currentProject: OpenCodeProject?
        let selectedDirectory: String?
    }

    struct RecentSessionNavigationResult {
        let projects: [OpenCodeProject]
        let currentProject: OpenCodeProject?
        let routeDirectory: String?
        let shouldPreserveMissingSession: Bool
    }

    struct RecentSessionResolutionResult {
        let session: OpenCodeSession?
        let shouldUpsertVisibleSession: Bool
    }

    func searchProjects(client: OpenCodeAPIClient, query: String, defaultSearchRoot: String) async -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        do {
            return try await client.findFiles(query: trimmedQuery, directory: defaultSearchRoot)
                .filter { $0.hasSuffix("/") }
                .map { value in
                    let trimmed = String(value.dropLast())
                    if trimmed.hasPrefix("/") { return trimmed }
                    return defaultSearchRoot + "/" + trimmed
                }
        } catch {
            return []
        }
    }

    func refreshProjects(
        client: OpenCodeAPIClient,
        currentProjects: [OpenCodeProject],
        currentProject: OpenCodeProject?,
        selectedDirectory: String?
    ) async throws -> ProjectRefreshResult {
        async let serverProjects = client.listProjects()
        async let serverProject = try? client.currentProject()
        let loadedProjects = try await serverProjects
        let discoveredProject = await serverProject
        let projects = mergeProjectsPreservingLocal(
            serverProjects: normalizedProjects(loadedProjects, currentProject: discoveredProject),
            currentProjects: currentProjects
        )
        let reconciledProject = reconcileCurrentProjectSelection(
            projects: projects,
            currentProject: currentProject,
            selectedDirectory: selectedDirectory,
            serverProject: discoveredProject
        )
        return ProjectRefreshResult(projects: projects, currentProject: reconciledProject)
    }

    func searchCreateProjectDirectories(
        client: OpenCodeAPIClient,
        query rawQuery: String,
        defaultSearchRoot: String
    ) async -> CreateProjectSearchResult {
        let query = cleanedDirectorySearchInput(rawQuery)

        do {
            if query.isEmpty {
                let results = try await client.listFiles(directory: "/")
                    .filter { $0.type == "directory" }
                    .map(\.absolute)
                return CreateProjectSearchResult(selectedDirectory: nil, results: results)
            }

            guard let scope = directorySearchScope(for: query, defaultSearchRoot: defaultSearchRoot) else {
                return CreateProjectSearchResult(selectedDirectory: nil, results: [])
            }

            if scope.isPathLike {
                let results = try await pathAutocompleteResults(for: scope, client: client)
                let selectedDirectory = try await resolveCreateProjectDirectory(for: query, scope: scope, client: client, defaultSearchRoot: defaultSearchRoot)
                return CreateProjectSearchResult(selectedDirectory: selectedDirectory, results: Array(results.prefix(50)))
            }

            let results = try await client.findFiles(query: query, directory: defaultSearchRoot)
                .filter { $0.hasSuffix("/") }
                .map { value in
                    let trimmed = String(value.dropLast())
                    if trimmed.hasPrefix("/") { return trimmed }
                    return defaultSearchRoot + "/" + trimmed
                }
            return CreateProjectSearchResult(selectedDirectory: nil, results: results)
        } catch {
            return CreateProjectSearchResult(selectedDirectory: nil, results: [])
        }
    }

    func createProjectResultPath(_ absolute: String, query rawQuery: String, defaultSearchRoot: String) -> String {
        let query = cleanedDirectorySearchInput(rawQuery)
        guard query.hasPrefix("~") else { return absolute }
        let home = defaultSearchRoot
        if absolute == home { return "~" }
        if absolute.hasPrefix(home + "/") {
            return "~" + String(absolute.dropFirst(home.count))
        }
        return absolute
    }

    func createProject(
        client: OpenCodeAPIClient,
        directory: String,
        currentProjects: [OpenCodeProject]
    ) async throws -> CreateProjectResult? {
        let normalizedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDirectory.isEmpty else { return nil }

        _ = try? await client.listSessions(directory: normalizedDirectory, roots: true, limit: 55)
        let discovered = try await client.currentProject(directory: normalizedDirectory)
        let projectName = URL(fileURLWithPath: normalizedDirectory).lastPathComponent

        if discovered.id == "global" {
            let localProject = OpenCodeProject(
                id: localProjectID(for: normalizedDirectory),
                worktree: normalizedDirectory,
                vcs: nil,
                name: projectName,
                sandboxes: nil,
                icon: nil,
                time: nil
            )
            return CreateProjectResult(
                projects: mergeProjectsPreservingLocal(serverProjects: currentProjects + [localProject], currentProjects: currentProjects),
                selectedDirectory: normalizedDirectory
            )
        }

        let canonicalDirectory = discovered.worktree
        _ = try await client.updateProject(projectID: discovered.id, directory: canonicalDirectory, name: projectName)
        return CreateProjectResult(projects: nil, selectedDirectory: canonicalDirectory)
    }

    func selectionResult(for project: OpenCodeProject?, projects: [OpenCodeProject]) -> ProjectSelectionResult {
        guard let project else {
            return ProjectSelectionResult(
                currentProject: projects.first(where: { $0.id == "global" }),
                selectedDirectory: nil
            )
        }

        if project.id == "global" {
            return ProjectSelectionResult(currentProject: project, selectedDirectory: nil)
        }

        return ProjectSelectionResult(currentProject: project, selectedDirectory: project.worktree)
    }

    func bootstrapProjects(_ serverProjects: [OpenCodeProject], currentProject: OpenCodeProject? = nil) -> [OpenCodeProject] {
        let projects = normalizedProjects(serverProjects, currentProject: currentProject)
        return mergeProjectsPreservingLocal(serverProjects: projects, currentProjects: projects)
    }

    func recentSessionDirectories(
        projects: [OpenCodeProject],
        currentProject: OpenCodeProject?,
        selectedDirectory: String?
    ) -> [String?] {
        var directories: [String?] = []
        var seen = Set<String>()

        appendRecentDirectory(nil, to: &directories, seen: &seen)
        appendRecentDirectory(selectedDirectory, to: &directories, seen: &seen)
        appendRecentProjectDirectories(currentProject, to: &directories, seen: &seen)

        for project in projects {
            appendRecentProjectDirectories(project, to: &directories, seen: &seen)
        }

        return directories
    }

    func recentSessionNavigationResult(for session: OpenCodeSession, projects: [OpenCodeProject]) -> RecentSessionNavigationResult {
        let resolvedProject = projectForRecentSession(session, projects: projects)
        var nextProjects = projects
        let currentProject: OpenCodeProject?

        if let resolvedProject {
            currentProject = resolvedProject
        } else if session.isGlobalScopeSession {
            let global = globalProject(in: nextProjects)
            if !nextProjects.contains(where: { $0.id == global.id }) {
                nextProjects.insert(global, at: 0)
            }
            currentProject = global
        } else {
            currentProject = nil
        }

        return RecentSessionNavigationResult(
            projects: nextProjects,
            currentProject: currentProject,
            routeDirectory: routeDirectory(forRecentSession: session),
            shouldPreserveMissingSession: session.isGlobalScopeSession
        )
    }

    func resolveRecentSessionAfterReload(
        recentSession: OpenCodeSession,
        matchingSession: OpenCodeSession?,
        allSessions: [OpenCodeSession]
    ) -> RecentSessionResolutionResult {
        if let matchingSession {
            return RecentSessionResolutionResult(session: matchingSession, shouldUpsertVisibleSession: false)
        }

        if let session = allSessions.first(where: { $0.id == recentSession.id }) {
            return RecentSessionResolutionResult(session: session, shouldUpsertVisibleSession: false)
        }

        guard recentSession.isGlobalScopeSession else {
            return RecentSessionResolutionResult(session: nil, shouldUpsertVisibleSession: false)
        }

        return RecentSessionResolutionResult(session: recentSession, shouldUpsertVisibleSession: true)
    }

    private func mergeProjectsPreservingLocal(serverProjects: [OpenCodeProject], currentProjects: [OpenCodeProject]) -> [OpenCodeProject] {
        let localProjects = currentProjects.filter { $0.id.hasPrefix("local:") || $0.id == "global" }
        var merged: [String: OpenCodeProject] = [:]

        for project in localProjects {
            merged[project.id] = project
        }

        for project in serverProjects {
            merged[project.id] = project
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.id == "global" { return true }
            if rhs.id == "global" { return false }
            return (lhs.name ?? lhs.worktree) < (rhs.name ?? rhs.worktree)
        }
    }

    private func localProjectID(for directory: String) -> String {
        "local:\(directory)"
    }

    private func normalizedProjects(_ serverProjects: [OpenCodeProject], currentProject: OpenCodeProject?) -> [OpenCodeProject] {
        var projects = serverProjects
        if let currentProject,
           !projects.contains(where: { $0.id == currentProject.id }) {
            projects.append(currentProject)
        }

        let global = globalProject(in: projects)
        if !projects.contains(where: { $0.id == global.id }) {
            projects.append(global)
        }

        return projects
    }

    private func appendRecentProjectDirectories(_ project: OpenCodeProject?, to directories: inout [String?], seen: inout Set<String>) {
        guard let project, project.id != "global" else { return }
        appendRecentDirectory(project.worktree, to: &directories, seen: &seen)
        for sandbox in project.sandboxes ?? [] {
            appendRecentDirectory(sandbox, to: &directories, seen: &seen)
        }
    }

    private func appendRecentDirectory(_ directory: String?, to directories: inout [String?], seen: inout Set<String>) {
        let key = recentDirectoryKey(directory)
        guard seen.insert(key).inserted else { return }
        if let directory, directory.isEmpty { return }
        directories.append(directory)
    }

    private func recentDirectoryKey(_ directory: String?) -> String {
        guard let directory, !directory.isEmpty else { return "global" }
        return directory
    }

    private func routeDirectory(forRecentSession session: OpenCodeSession) -> String? {
        session.isGlobalScopeSession ? nil : session.directory
    }

    private func projectForRecentSession(_ session: OpenCodeSession, projects: [OpenCodeProject]) -> OpenCodeProject? {
        if let projectID = session.projectID,
           let project = projects.first(where: { $0.id == projectID }) {
            return project
        }

        guard !session.isGlobalScopeSession,
              let directory = session.directory,
              !directory.isEmpty else {
            return projects.first { $0.id == "global" }
        }

        return projects.first { project in
            project.worktree == directory || (project.sandboxes ?? []).contains(directory)
        }
    }

    private func globalProject(in projects: [OpenCodeProject]) -> OpenCodeProject {
        projects.first { $0.id == "global" } ?? OpenCodeProject(
            id: "global",
            worktree: "",
            vcs: nil,
            name: "Global",
            sandboxes: nil,
            icon: nil,
            time: nil
        )
    }

    private func reconcileCurrentProjectSelection(
        projects: [OpenCodeProject],
        currentProject: OpenCodeProject?,
        selectedDirectory: String?,
        serverProject: OpenCodeProject?
    ) -> OpenCodeProject? {
        if let selectedDirectory, !selectedDirectory.isEmpty {
            return projects.first(where: { $0.worktree == selectedDirectory })
                ?? serverProject.flatMap { project in
                    project.worktree == selectedDirectory ? project : nil
                }
        }

        guard currentProject != nil else { return currentProject }

        return projects.first(where: { $0.id == "global" })
            ?? serverProject.flatMap { project in
                project.id == "global" ? project : nil
            }
    }

    private func cleanedDirectorySearchInput(_ value: String) -> String {
        value
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func directorySearchScope(for query: String, defaultSearchRoot: String) -> DirectorySearchScope? {
        if query.hasPrefix("~/") {
            return .init(directory: defaultSearchRoot, path: String(query.dropFirst(2)), isPathLike: true)
        }

        if query == "~" {
            return .init(directory: defaultSearchRoot, path: "", isPathLike: true)
        }

        if query.hasPrefix("/") {
            return .init(directory: "/", path: String(query.dropFirst()), isPathLike: true)
        }

        if query.contains("/") {
            return .init(directory: defaultSearchRoot, path: query, isPathLike: true)
        }

        return .init(directory: defaultSearchRoot, path: query, isPathLike: false)
    }

    private func pathAutocompleteResults(for scope: DirectorySearchScope, client: OpenCodeAPIClient) async throws -> [String] {
        let normalizedPath = scope.path.replacingOccurrences(of: "//", with: "/")
        let trimmedTrailingSlash = normalizedPath.hasSuffix("/") ? String(normalizedPath.dropLast()) : normalizedPath

        let parentPath: String
        let partialName: String
        let shouldListChildrenDirectly = normalizedPath.isEmpty || normalizedPath.hasSuffix("/")

        if shouldListChildrenDirectly {
            parentPath = trimmedTrailingSlash
            partialName = ""
        } else if let slashIndex = trimmedTrailingSlash.lastIndex(of: "/") {
            parentPath = String(trimmedTrailingSlash[..<slashIndex])
            partialName = String(trimmedTrailingSlash[trimmedTrailingSlash.index(after: slashIndex)...])
        } else {
            parentPath = ""
            partialName = trimmedTrailingSlash
        }

        let nodes = try await client.listFiles(directory: scope.directory, path: parentPath)
        let directories = nodes
            .filter { $0.type == "directory" }
            .map(\.absolute)

        guard !partialName.isEmpty else {
            return directories.sorted()
        }

        let lowercasedPartial = partialName.lowercased()
        let prefixMatches = directories.filter {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased().hasPrefix(lowercasedPartial)
        }
        if !prefixMatches.isEmpty {
            return prefixMatches.sorted()
        }

        let containsMatches = directories.filter {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased().contains(lowercasedPartial)
        }
        return containsMatches.sorted()
    }

    private func resolveCreateProjectDirectory(for query: String, scope: DirectorySearchScope, client: OpenCodeAPIClient, defaultSearchRoot: String) async throws -> String? {
        guard scope.isPathLike,
              let candidate = absoluteDirectoryCandidate(for: query, scope: scope, defaultSearchRoot: defaultSearchRoot) else {
            return nil
        }

        _ = try await client.listFiles(directory: candidate, path: "")
        return candidate
    }

    private func absoluteDirectoryCandidate(for query: String, scope: DirectorySearchScope, defaultSearchRoot: String) -> String? {
        if query == "~" || query == "~/" {
            return defaultSearchRoot
        }

        if query == "/" {
            return "/"
        }

        let trimmedPath = scope.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            return scope.directory
        }

        let baseURL = URL(fileURLWithPath: scope.directory, isDirectory: true)
        return baseURL.appendingPathComponent(trimmedPath, isDirectory: true).path
    }
}
