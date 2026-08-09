import XCTest
@testable import OpenClient

@MainActor
final class WidgetSnapshotBuilderTests: XCTestCase {
    func testBuilderProducesScopedSessionSnapshotWithoutCredentials() throws {
        let now = Date(timeIntervalSince1970: 1_234)
        let project = OpenCodeProject(
            id: "project",
            worktree: "/tmp/project",
            vcs: "git",
            name: "Project",
            sandboxes: nil,
            icon: nil,
            time: nil
        )
        let session = OpenCodeSession(
            id: "ses_1",
            title: "Session",
            workspaceID: nil,
            directory: project.worktree,
            projectID: project.id,
            parentID: nil
        )
        let preview = SessionPreview(text: "Latest answer", date: now.addingTimeInterval(-10))
        let config = OpenCodeServerConfig(
            name: "Studio",
            baseURL: "https://example.com",
            username: "nick",
            password: "secret"
        )

        let publication = try XCTUnwrap(WidgetSnapshotBuilder.build(
            from: WidgetSnapshotInput(
                backendMode: .server,
                config: config,
                projects: [project],
                currentProject: project,
                effectiveDirectory: project.worktree,
                sessions: [session],
                sessionTitlesByID: [session.id: "Session"],
                statuses: [session.id: "busy"],
                previews: [session.id: preview],
                pinnedSessionIDs: [session.id],
                permissionsBySessionID: [:],
                questionsBySessionID: [:],
                commands: [],
                providers: [],
                visibleModelsByProviderID: [:]
            ),
            includeModelOptions: false,
            now: now
        ))

        XCTAssertEqual(publication.server.baseURL, "https://example.com")
        XCTAssertEqual(publication.server.username, "nick")
        XCTAssertFalse(String(describing: publication.server).contains("secret"))
        XCTAssertEqual(publication.sessions.first?.projectID, project.id)
        XCTAssertEqual(publication.sessions.first?.status, .working)
        XCTAssertEqual(publication.sessions.first?.summaryText, preview.text)
        XCTAssertEqual(publication.sessions.first?.pinOrder, 0)
    }

    func testBuilderPrioritizesPermissionAndNormalizesGlobalCommandDirectory() throws {
        let session = OpenCodeSession(
            id: "ses_global",
            title: "Global",
            workspaceID: nil,
            directory: nil,
            projectID: "global",
            parentID: nil
        )
        let permission = OpenCodePermission(
            id: "perm_1",
            sessionID: session.id,
            permission: "bash",
            patterns: ["git status"],
            always: nil,
            metadata: nil,
            tool: nil
        )
        let global = OpenCodeProject(id: "global", worktree: "", vcs: nil, name: "Global", sandboxes: nil, icon: nil, time: nil)
        let command = OpenCodeCommand(
            name: "review",
            description: "Review",
            agent: nil,
            model: nil,
            source: "project",
            template: "review",
            subtask: false,
            hints: []
        )
        let publication = try XCTUnwrap(WidgetSnapshotBuilder.build(
            from: WidgetSnapshotInput(
                backendMode: .server,
                config: OpenCodeServerConfig(baseURL: "https://example.com", username: "nick", password: "secret"),
                projects: [global],
                currentProject: global,
                effectiveDirectory: nil,
                sessions: [session],
                sessionTitlesByID: [:],
                statuses: [session.id: "idle"],
                previews: [session.id: SessionPreview(text: "Stale", date: nil)],
                pinnedSessionIDs: [],
                permissionsBySessionID: [session.id: [permission]],
                questionsBySessionID: [:],
                commands: [command],
                providers: [],
                visibleModelsByProviderID: [:]
            ),
            includeModelOptions: false
        ))

        XCTAssertEqual(publication.sessions.first?.summaryKind, .permission)
        XCTAssertEqual(publication.sessions.first?.status, .needsAction)
        XCTAssertNil(publication.commands.first?.directory)
    }

    func testViewModelInputSkipsChildSessionsThatWidgetsDoNotPublish() {
        let root = OpenCodeSession(
            id: "ses_root",
            title: "Root",
            workspaceID: nil,
            directory: "/tmp/project",
            projectID: "project",
            parentID: nil
        )
        let child = OpenCodeSession(
            id: "ses_child",
            title: "Child",
            workspaceID: nil,
            directory: root.directory,
            projectID: root.projectID,
            parentID: root.id
        )
        let viewModel = AppViewModel()
        viewModel.config = OpenCodeServerConfig(
            baseURL: "https://example.com",
            username: "nick",
            password: "secret"
        )
        viewModel.allSessions = [root, child]

        let input = viewModel.widgetSnapshotInput()

        XCTAssertEqual(input.sessions.map(\.id), [root.id])
    }

    func testViewModelInputStopsPreparingModelsAtWidgetLimit() {
        let providers = (0 ..< 5).map { providerIndex in
            let providerID = "provider-\(providerIndex)"
            let models = Dictionary(uniqueKeysWithValues: (0 ..< 50).map { modelIndex in
                let modelID = "model-\(modelIndex)"
                return (
                    modelID,
                    OpenCodeModel(
                        id: modelID,
                        providerID: providerID,
                        name: modelID,
                        capabilities: OpenCodeModelCapabilities(reasoning: false)
                    )
                )
            })
            return OpenCodeProvider(id: providerID, name: providerID, models: models)
        }
        let viewModel = AppViewModel()
        viewModel.modelConfigurationStore.applyProviderState(
            OpenCodeProviderListResponse(
                all: providers,
                connected: providers.map(\.id),
                default: [:]
            )
        )

        let input = viewModel.widgetSnapshotInput(includeModelOptions: true)

        XCTAssertEqual(input.providers.count, 3)
        XCTAssertEqual(input.visibleModelsByProviderID.values.reduce(0) { $0 + $1.count }, 120)
    }

    func testPublisherWritesAndReloadsOnlyRelevantTimelines() async {
        let writer = WidgetWriterSpy()
        let reloader = WidgetTimelineReloaderSpy()
        let publisher = WidgetSnapshotPublisher(
            inputProvider: { _ in self.emptyInput() },
            writer: writer,
            timelineReloader: reloader
        )

        await publisher.publishNow()
        XCTAssertEqual(writer.updateCount, 1)
        XCTAssertEqual(reloader.contentReloadCount, 1)
        XCTAssertEqual(reloader.shortcutReloadCount, 0)

        await publisher.publishNow(includeModelOptions: true)
        XCTAssertEqual(writer.updateCount, 2)
        XCTAssertEqual(reloader.contentReloadCount, 2)
        XCTAssertEqual(reloader.shortcutReloadCount, 1)
    }

    private func emptyInput() -> WidgetSnapshotInput {
        WidgetSnapshotInput(
            backendMode: .server,
            config: OpenCodeServerConfig(baseURL: "https://example.com", username: "nick", password: "secret"),
            projects: [],
            currentProject: nil,
            effectiveDirectory: nil,
            sessions: [],
            sessionTitlesByID: [:],
            statuses: [:],
            previews: [:],
            pinnedSessionIDs: [],
            permissionsBySessionID: [:],
            questionsBySessionID: [:],
            commands: [],
            providers: [],
            visibleModelsByProviderID: [:]
        )
    }
}

private final class WidgetWriterSpy: WidgetSnapshotWriting {
    var updateCount = 0
    var removedSessions: [(String, String)] = []

    func update(_ publication: WidgetServerPublication) {
        updateCount += 1
    }

    func removeSession(serverID: String, sessionID: String) {
        removedSessions.append((serverID, sessionID))
    }
}

private final class WidgetTimelineReloaderSpy: WidgetTimelineReloading {
    var contentReloadCount = 0
    var shortcutReloadCount = 0

    func reloadContentTimelines() { contentReloadCount += 1 }
    func reloadShortcutTimelines() { shortcutReloadCount += 1 }
    func reloadAllTimelines() {
        contentReloadCount += 1
        shortcutReloadCount += 1
    }
}
