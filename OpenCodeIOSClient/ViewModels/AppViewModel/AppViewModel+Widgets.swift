import Foundation

extension AppViewModel {
    func widgetSnapshotInput(includeModelOptions: Bool = false) -> WidgetSnapshotInput {
        let sessions = allSessions
        let providers = includeModelOptions ? modelConfigurationStore.sortedProviders : []
        return WidgetSnapshotInput(
            backendMode: backendMode,
            config: config,
            projects: projects,
            currentProject: currentProject,
            effectiveDirectory: effectiveSelectedDirectory,
            sessions: sessions,
            sessionTitlesByID: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, childSessionTitle(for: $0)) }),
            statuses: sessionStatuses,
            previews: sessionPreviews,
            pinnedSessionIDs: pinnedSessionIDs,
            permissionsBySessionID: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, permissions(for: $0.id)) }),
            questionsBySessionID: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, questions(for: $0.id)) }),
            commands: directoryCommands,
            providers: providers,
            visibleModelsByProviderID: Dictionary(uniqueKeysWithValues: providers.map {
                ($0.id, modelConfigurationStore.visibleModels(for: $0))
            })
        )
    }

    func scheduleWidgetSnapshotPublication(includeModelOptions: Bool = false) {
        widgetSnapshotPublisher.invalidate(includeModelOptions: includeModelOptions)
    }

    func publishWidgetSnapshots(includeModelOptions: Bool = false) {
        scheduleWidgetSnapshotPublication(includeModelOptions: includeModelOptions)
    }

    func removeWidgetSessionSnapshot(for sessionID: String) {
        guard config.hasCredentials else { return }
        widgetSnapshotPublisher.removeSession(serverID: config.recentServerID, sessionID: sessionID)
    }
}
