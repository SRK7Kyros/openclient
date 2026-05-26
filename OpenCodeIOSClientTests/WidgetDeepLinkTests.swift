import XCTest
@testable import OpenClient

final class WidgetDeepLinkTests: XCTestCase {
    private let widgetStorageKey = "OpenCodeWidgetSnapshotPayload"

    override func setUp() {
        super.setUp()
        clearWidgetPayloadStorage()
    }

    override func tearDown() {
        clearWidgetPayloadStorage()
        super.tearDown()
    }

    func testActionWidgetDeepLinkRoundTrips() throws {
        let url = try XCTUnwrap(OpenCodeWidgetDeepLink.actionURL(
            serverID: "server_1",
            projectID: "proj_1",
            directory: "/tmp/project",
            commandName: "test",
            providerID: "openai",
            modelID: "gpt-5",
            reasoningVariant: "balanced"
        ))

        let request = try XCTUnwrap(OpenCodeWidgetDeepLink.request(from: url))

        XCTAssertEqual(request.kind, .action(commandName: "test"))
        XCTAssertEqual(request.serverID, "server_1")
        XCTAssertEqual(request.projectID, "proj_1")
        XCTAssertEqual(request.directory, "/tmp/project")
        XCTAssertEqual(request.providerID, "openai")
        XCTAssertEqual(request.modelID, "gpt-5")
        XCTAssertEqual(request.reasoningVariant, "balanced")
    }

    func testNewSessionWidgetDeepLinkRoundTrips() throws {
        let url = try XCTUnwrap(OpenCodeWidgetDeepLink.newSessionURL(
            serverID: "server_1",
            projectID: "global",
            directory: nil,
            providerID: "anthropic",
            modelID: "claude-opus-4-1",
            reasoningVariant: nil
        ))

        let request = try XCTUnwrap(OpenCodeWidgetDeepLink.request(from: url))

        XCTAssertEqual(request.kind, .newSession)
        XCTAssertEqual(request.serverID, "server_1")
        XCTAssertEqual(request.projectID, "global")
        XCTAssertNil(request.directory)
        XCTAssertEqual(request.providerID, "anthropic")
        XCTAssertEqual(request.modelID, "claude-opus-4-1")
        XCTAssertNil(request.reasoningVariant)
    }

    func testActionWidgetDeepLinkRequiresCommand() {
        XCTAssertNil(OpenCodeWidgetDeepLink.actionURL(
            serverID: "server_1",
            projectID: "proj_1",
            directory: "/tmp/project",
            commandName: nil,
            providerID: nil,
            modelID: nil,
            reasoningVariant: nil
        ))

        XCTAssertNil(OpenCodeWidgetDeepLink.actionURL(
            serverID: "server_1",
            projectID: "proj_1",
            directory: "/tmp/project",
            commandName: "",
            providerID: nil,
            modelID: nil,
            reasoningVariant: nil
        ))
    }

    func testWidgetPayloadDecodesOlderSnapshotsWithoutShortcutMetadata() throws {
        let data = """
        {
          "servers": [],
          "projects": [],
          "sessions": [],
          "generatedAt": 0
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(OpenCodeWidgetSnapshotPayload.self, from: data)

        XCTAssertEqual(payload.commands, [])
        XCTAssertEqual(payload.models, [])
    }

    func testControlWidgetKindsAreStableAndDistinct() {
        XCTAssertEqual(OpenCodeWidgetKind.newSessionControl, "OpenCodeNewSessionControl")
        XCTAssertEqual(OpenCodeWidgetKind.actionControl, "OpenCodeActionControl")
        XCTAssertNotEqual(OpenCodeWidgetKind.newSessionControl, OpenCodeWidgetKind.newSessionShortcut)
        XCTAssertNotEqual(OpenCodeWidgetKind.actionControl, OpenCodeWidgetKind.actionShortcut)
    }

    func testWidgetStoreCapsPersistedModelsPerServer() {
        let models = (0 ..< 140).map { index in
            OpenCodeWidgetModelSnapshot(
                id: "server_1|provider|model_\(index)",
                serverID: "server_1",
                providerID: "provider",
                providerName: "Provider",
                modelID: "model_\(index)",
                modelName: "Model \(index)",
                reasoningVariants: [],
                sortTitle: "provider model \(index)"
            )
        }
        let payload = OpenCodeWidgetSnapshotPayload(
            servers: [OpenCodeWidgetServerSnapshot(
                id: "server_1",
                displayName: "Server",
                baseURL: "http://localhost:4096",
                username: "",
                generatedAt: Date(timeIntervalSince1970: 0),
                isLastConnected: true
            )],
            projects: [],
            sessions: [],
            models: models,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        OpenCodeWidgetStore().save(payload)

        let loaded = OpenCodeWidgetStore().load()
        XCTAssertEqual(loaded.models.count, 120)
        XCTAssertEqual(loaded.models.first?.modelID, "model_0")
        XCTAssertEqual(loaded.models.last?.modelID, "model_119")
    }

    func testWidgetStoreDropsOversizedPayloadWithoutDecoding() {
        widgetDefaults().set(Data(repeating: 0, count: 1_000_001), forKey: widgetStorageKey)

        XCTAssertEqual(OpenCodeWidgetStore().load(), .empty)
    }

    private func widgetDefaults() -> UserDefaults {
        UserDefaults(suiteName: OpenCodeWidgetStore.appGroupIdentifier) ?? .standard
    }

    private func clearWidgetPayloadStorage() {
        UserDefaults(suiteName: OpenCodeWidgetStore.appGroupIdentifier)?.removeObject(forKey: widgetStorageKey)
        UserDefaults.standard.removeObject(forKey: widgetStorageKey)
    }
}
