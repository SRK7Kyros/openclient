import Combine
import Foundation
import SwiftUI

@MainActor
final class ProjectFilesFacade: ObservableObject {
    struct FileTreeRow: Identifiable, Hashable {
        let node: OpenCodeFileNode
        let depth: Int

        var id: String { node.absolute }
    }

    struct Snapshot: Hashable {
        let vcsInfo: OpenCodeVCSInfo?
        let summary: OpenCodeVCSSummary
        let intensityFiles: [OpenCodeVCSIntensityFile]
        let fileStatuses: [OpenCodeVCSFileStatus]
        let selectedMode: OpenCodeVCSDiffMode
        let selectedVCSFile: String?
        let filesMode: OpenCodeProjectFilesMode
        let selectedFilePath: String?
        let visibleRows: [FileTreeRow]
        let isLoadingVCS: Bool
        let isLoadingFileTree: Bool
        let vcsErrorMessage: String?
        let fileTreeErrorMessage: String?
        let selectedFileContent: OpenCodeFileContent?
        let selectedFileDiff: OpenCodeVCSFileDiff?
        let selectedFileIsChanged: Bool
        let isLoadingSelectedFileContent: Bool
        let fileContentErrorMessage: String?
        let effectiveDirectory: String?
    }

    private let store: ProjectFilesStore
    private let clientProvider: () -> OpenCodeAPIClient?
    private let hasGitProjectProvider: () -> Bool
    private let effectiveSelectedDirectoryProvider: () -> String?
    private let currentProjectProvider: () -> OpenCodeProject?
    private let workspaceDirectoriesProvider: () -> [String]
    private let workspaceDisplayNameProvider: (String?) -> String?
    private let workspaceKeyProvider: (String) -> String
    private let isFilesPresentedProvider: () -> Bool
    private let preserveNavigationState: () -> Void
    private let showFilesRoute: () -> Void
    private var observation: AnyCancellable?
    private var eventRefreshTask: Task<Void, Never>?

    @Published var selectedWorkspaceDirectory: String?

    init(
        store: ProjectFilesStore,
        clientProvider: @escaping () -> OpenCodeAPIClient?,
        hasGitProjectProvider: @escaping () -> Bool,
        effectiveSelectedDirectoryProvider: @escaping () -> String?,
        currentProjectProvider: @escaping () -> OpenCodeProject?,
        workspaceDirectoriesProvider: @escaping () -> [String],
        workspaceDisplayNameProvider: @escaping (String?) -> String?,
        workspaceKeyProvider: @escaping (String) -> String,
        isFilesPresentedProvider: @escaping () -> Bool,
        preserveNavigationState: @escaping () -> Void,
        showFilesRoute: @escaping () -> Void,
        selectedWorkspaceDirectory: String? = nil
    ) {
        self.store = store
        self.clientProvider = clientProvider
        self.hasGitProjectProvider = hasGitProjectProvider
        self.effectiveSelectedDirectoryProvider = effectiveSelectedDirectoryProvider
        self.currentProjectProvider = currentProjectProvider
        self.workspaceDirectoriesProvider = workspaceDirectoriesProvider
        self.workspaceDisplayNameProvider = workspaceDisplayNameProvider
        self.workspaceKeyProvider = workspaceKeyProvider
        self.isFilesPresentedProvider = isFilesPresentedProvider
        self.preserveNavigationState = preserveNavigationState
        self.showFilesRoute = showFilesRoute
        self.selectedWorkspaceDirectory = selectedWorkspaceDirectory
        observation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var snapshot: Snapshot {
        let path = store.selectedFilePath
        let diffs = store.currentDiffs()
        return Snapshot(
            vcsInfo: store.vcsInfo,
            summary: store.vcsSummary,
            intensityFiles: intensityFiles,
            fileStatuses: store.vcsFileStatuses,
            selectedMode: store.selectedVCSMode,
            selectedVCSFile: store.selectedVCSFile,
            filesMode: store.mode,
            selectedFilePath: path,
            visibleRows: flattenFileTree(nodes: store.fileTreeRootNodes, depth: 0),
            isLoadingVCS: store.isLoadingVCS,
            isLoadingFileTree: store.isLoadingFileTree,
            vcsErrorMessage: store.vcsErrorMessage,
            fileTreeErrorMessage: store.fileTreeErrorMessage,
            selectedFileContent: path.flatMap { store.fileContentsByPath[$0] },
            selectedFileDiff: (path ?? store.selectedVCSFile).flatMap { selectedPath in
                diffs.first { $0.file == selectedPath }
            },
            selectedFileIsChanged: path.map { selectedPath in
                store.vcsFileStatuses.contains { $0.path == selectedPath }
            } ?? false,
            isLoadingSelectedFileContent: store.isLoadingSelectedFileContent,
            fileContentErrorMessage: store.fileContentErrorMessage,
            effectiveDirectory: effectiveDirectory
        )
    }

    var hasGitProject: Bool { hasGitProjectProvider() }
    var workspaceDirectories: [String] { workspaceDirectoriesProvider() }

    var effectiveDirectory: String? {
        guard hasGitProject else { return effectiveSelectedDirectoryProvider() }
        let directories = workspaceDirectories
        guard !directories.isEmpty else { return effectiveSelectedDirectoryProvider() }

        if let selectedWorkspaceDirectory,
           directories.contains(where: { workspaceKeyProvider($0) == workspaceKeyProvider(selectedWorkspaceDirectory) }) {
            return selectedWorkspaceDirectory
        }

        return currentProjectProvider()?.worktree ?? effectiveSelectedDirectoryProvider()
    }

    var availableDiffModes: [OpenCodeVCSDiffMode] {
        store.availableDiffModes(hasGitProject: hasGitProject)
    }

    func workspaceDisplayName(for directory: String?) -> String? {
        workspaceDisplayNameProvider(directory)
    }

    func relativeGitPath(_ path: String) -> String {
        store.relativeGitPath(path, effectiveDirectory: effectiveDirectory)
    }

    func isExpandedDirectory(_ path: String) -> Bool {
        store.isExpandedDirectory(path)
    }

    func isChangedFile(_ path: String) -> Bool {
        store.isChangedFile(path, effectiveDirectory: effectiveDirectory)
    }

    func changedStatus(for path: String) -> OpenCodeVCSFileStatus? {
        store.changedStatus(for: path, effectiveDirectory: effectiveDirectory)
    }

    func aggregateStatus(for node: OpenCodeFileNode) -> OpenCodeVCSAggregateStatus? {
        store.aggregateStatus(for: node, effectiveDirectory: effectiveDirectory)
    }

    func prepareForPresentation() {
        guard hasGitProject else { return }
        if selectedWorkspaceDirectory == nil {
            selectedWorkspaceDirectory = currentProjectProvider()?.worktree
        }
    }

    func selectWorkspaceDirectory(_ directory: String) {
        guard workspaceDirectories.contains(where: { workspaceKeyProvider($0) == workspaceKeyProvider(directory) }) else { return }
        guard selectedWorkspaceDirectory.map(workspaceKeyProvider) != workspaceKeyProvider(directory) else { return }

        preserveNavigationState()
        withAnimation(opencodeSelectionAnimation) {
            selectedWorkspaceDirectory = directory
            store.selectedVCSMode = .git
            store.clearWorkspaceData()
        }

        Task {
            await reloadGitViewData(force: true)
            if store.mode == .tree {
                await reloadFileTree(force: true)
            }
        }
    }

    func selectFilesMode(_ mode: OpenCodeProjectFilesMode) {
        guard store.selectMode(mode) else { return }
        if mode == .tree {
            Task { await loadFileTreeIfNeeded() }
        }
    }

    func selectVCSMode(_ mode: OpenCodeVCSDiffMode) {
        guard store.selectVCSMode(mode, availableModes: availableDiffModes) else { return }
        Task { await loadVCSDiff(mode: mode) }
    }

    func selectVCSFile(_ path: String) {
        preserveNavigationState()
        showFilesRoute()
        withAnimation(opencodeSelectionAnimation) {
            store.selectVCSFile(path)
        }
        Task { await loadVCSDiff(mode: store.selectedVCSMode) }
    }

    func selectProjectFile(_ node: OpenCodeFileNode) {
        guard !node.isDirectory else { return }
        preserveNavigationState()
        showFilesRoute()

        let changed = isChangedFile(node.absolute)
        withAnimation(opencodeSelectionAnimation) {
            store.selectProjectFile(node, isChanged: changed)
        }

        guard !changed || OpenCodeFilePreviewSupport.isImagePath(node.absolute) else { return }
        Task { await loadFileContentIfNeeded(for: node) }
    }

    func toggleDirectory(_ node: OpenCodeFileNode) {
        guard store.toggleDirectory(node) else { return }
        Task { await loadFileTreeChildren(for: node, force: false) }
    }

    func loadFileTreeIfNeeded() async {
        guard hasGitProject, store.needsFileTreeRootLoad() else { return }
        await reloadFileTree(force: false)
    }

    func reloadFileTree(force: Bool) async {
        guard hasGitProject, let directory = effectiveDirectory, let client = clientProvider() else { return }
        store.isLoadingFileTree = true
        if force { store.fileTreeErrorMessage = nil }
        defer { store.isLoadingFileTree = false }

        do {
            let nodes = try await client.listFiles(directory: directory, path: "")
            store.applyLoadedRootNodes(nodes)
        } catch {
            store.fileTreeErrorMessage = error.localizedDescription
        }
    }

    func loadSelectedFileContentIfNeeded() async {
        guard let path = store.selectedFilePath,
              store.needsFileContent(path: path),
              !snapshot.selectedFileIsChanged || OpenCodeFilePreviewSupport.isImagePath(path) else {
            return
        }
        await loadFileContent(path: path, force: false)
    }

    func loadGitViewDataIfNeeded() async {
        guard hasGitProject, store.needsGitViewLoad() else { return }
        await reloadGitViewData(force: false)
    }

    func refresh() async {
        await reloadGitViewData(force: true)
        if store.mode == .tree {
            await reloadFileTree(force: true)
        }
    }

    func reloadGitViewData(force: Bool) async {
        guard hasGitProject, let directory = effectiveDirectory, let client = clientProvider() else { return }
        withAnimation(opencodeSelectionAnimation) {
            store.isLoadingVCS = true
            if force { store.vcsErrorMessage = nil }
        }
        defer { store.isLoadingVCS = false }

        do {
            async let info = client.getVCSInfo(directory: directory)
            async let status = client.listFileStatus(directory: directory)

            let loadedInfo = try await info
            store.applyLoadedVCSInfo(loadedInfo, hasGitProject: hasGitProject)

            let loadedStatus = try await status
            store.applyLoadedVCSStatus(loadedStatus, relativePath: relativeGitPath)

            if force || loadedStatus.isEmpty || store.vcsDiffsByMode[store.selectedVCSMode] != nil {
                let loadedDiff = try await client.getVCSDiff(mode: store.selectedVCSMode, directory: directory)
                store.applyLoadedVCSDiff(loadedDiff, mode: store.selectedVCSMode, relativePath: relativeGitPath)
            }
            store.vcsErrorMessage = nil
        } catch {
            store.vcsErrorMessage = error.localizedDescription
        }
    }

    func loadVCSDiff(mode: OpenCodeVCSDiffMode, force: Bool = false) async {
        guard hasGitProject, let directory = effectiveDirectory, let client = clientProvider() else { return }
        if !store.needsDiffLoad(mode: mode, force: force) {
            store.selectReasonableVCSFileIfNeeded()
            return
        }

        store.isLoadingVCS = true
        defer { store.isLoadingVCS = false }
        do {
            let diff = try await client.getVCSDiff(mode: mode, directory: directory)
            store.applyLoadedVCSDiff(diff, mode: mode, relativePath: relativeGitPath)
            store.vcsErrorMessage = nil
        } catch {
            store.vcsErrorMessage = error.localizedDescription
        }
    }

    func handleBranchUpdate(_ branch: String?) {
        store.applyBranchUpdate(branch)
        refreshFromEvent()
    }

    func handleFileWatcherUpdate(_ file: String) {
        guard !file.isEmpty else { return }
        // Working-tree edits and Git metadata changes can both alter VCS status.
        refreshFromEvent()
    }

    func refreshFromEvent() {
        guard hasGitProject else { return }
        eventRefreshTask?.cancel()
        eventRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.hasGitProject, self.isFilesPresentedProvider() else { return }
            await self.reloadGitViewData(force: true)
            self.eventRefreshTask = nil
        }
    }

    func reset() {
        eventRefreshTask?.cancel()
        eventRefreshTask = nil
        selectedWorkspaceDirectory = nil
        store.reset()
    }

    private var intensityFiles: [OpenCodeVCSIntensityFile] {
        store.vcsFileStatuses.map { status in
            OpenCodeVCSIntensityFile(
                path: status.path,
                status: status.status,
                additions: status.added,
                deletions: status.removed,
                relativePath: relativeGitPath(status.path),
                score: status.added + status.removed
            )
        }
    }

    private func loadFileTreeChildren(for node: OpenCodeFileNode, force: Bool) async {
        guard store.needsChildrenLoad(for: node, force: force),
              let directory = effectiveDirectory,
              let client = clientProvider() else { return }
        store.isLoadingFileTree = true
        defer { store.isLoadingFileTree = false }
        do {
            let nodes = try await client.listFiles(directory: directory, path: node.path)
            store.applyLoadedChildren(nodes, for: node)
        } catch {
            store.fileTreeErrorMessage = error.localizedDescription
        }
    }

    private func loadFileContentIfNeeded(for node: OpenCodeFileNode) async {
        guard !node.isDirectory, store.needsFileContent(path: node.absolute) else { return }
        await loadFileContent(path: node.absolute, requestPath: node.path, force: false)
    }

    private func loadFileContent(path: String, force: Bool) async {
        guard let directory = effectiveDirectory else { return }
        await loadFileContent(
            path: path,
            requestPath: store.relativeFileRequestPath(for: path, directory: directory),
            force: force
        )
    }

    private func loadFileContent(path: String, requestPath: String, force: Bool) async {
        guard let directory = effectiveDirectory,
              store.needsFileContent(path: path, force: force),
              let client = clientProvider() else { return }
        store.isLoadingSelectedFileContent = true
        defer { store.isLoadingSelectedFileContent = false }
        do {
            let content = try await client.readFileContent(directory: directory, path: requestPath)
            store.applyLoadedFileContent(content, path: path)
        } catch {
            store.fileContentErrorMessage = error.localizedDescription
        }
    }

    private func flattenFileTree(nodes: [OpenCodeFileNode], depth: Int) -> [FileTreeRow] {
        var rows: [FileTreeRow] = []
        for node in nodes {
            rows.append(FileTreeRow(node: node, depth: depth))
            guard node.isDirectory,
                  store.isExpandedDirectory(node.absolute),
                  let children = store.fileTreeChildrenByParentPath[node.absolute] else {
                continue
            }
            rows.append(contentsOf: flattenFileTree(nodes: children, depth: depth + 1))
        }
        return rows
    }
}
