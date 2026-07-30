import Foundation
import XCTest
@testable import OpenClient

final class TerminalFeatureTests: XCTestCase {
    func testPTYCreatedEventDecodesFromGlobalStream() throws {
        let raw = #"{"directory":"/tmp/project","payload":{"type":"pty.created","properties":{"info":{"id":"pty_1","title":"Terminal 1","command":"/bin/zsh","args":["-l"],"cwd":"/tmp/project","status":"running","pid":42}}}}"#

        guard case let .event(event) = OpenCodeEventManager.decodeManagedEvent(from: raw),
              case let .ptyCreated(terminal) = event.typed else {
            return XCTFail("Expected a typed pty.created event")
        }

        XCTAssertEqual(event.directory, "/tmp/project")
        XCTAssertEqual(terminal.id, "pty_1")
        XCTAssertEqual(terminal.command, "/bin/zsh")
        XCTAssertEqual(terminal.args, ["-l"])
        XCTAssertEqual(terminal.pid, 42)
    }

    func testPTYExitedEventDecodesExitCode() throws {
        let raw = #"{"directory":"/tmp/project","payload":{"type":"pty.exited","properties":{"id":"pty_1","exitCode":130}}}"#

        guard case let .event(event) = OpenCodeEventManager.decodeManagedEvent(from: raw),
              case let .ptyExited(id, exitCode) = event.typed else {
            return XCTFail("Expected a typed pty.exited event")
        }

        XCTAssertEqual(id, "pty_1")
        XCTAssertEqual(exitCode, 130)
    }

    func testBinaryCursorMetadataDecodes() {
        var data = Data([0])
        data.append(Data(#"{"cursor":12345}"#.utf8))

        XCTAssertEqual(OpenCodePTYConnection.decodeCursorMetadata(data), 12_345)
        XCTAssertNil(OpenCodePTYConnection.decodeCursorMetadata(Data(#"{"cursor":12}"#.utf8)))
    }

    func testSoftwareTerminalInputSendsTextAndCarriageReturnBytes() {
        XCTAssertEqual(TerminalFacade.softwareInputBytes(for: "pwd"), Array("pwd".utf8))
        XCTAssertEqual(TerminalFacade.softwareInputBytes(for: "\n"), [0x0D])
        XCTAssertEqual(TerminalFacade.softwareInputBytes(for: "\r"), [0x0D])
        XCTAssertEqual(TerminalFacade.softwareInputBytes(for: "\r\n"), [0x0D])
    }

    func testFreshRendererReplaysBeforeReconnectResumesFromLatestCursor() {
        XCTAssertEqual(
            TerminalFacade.connectionCursor(initialCursor: 0, latestCursor: 912, attempt: 0),
            0
        )
        XCTAssertEqual(
            TerminalFacade.connectionCursor(initialCursor: 0, latestCursor: 912, attempt: 1),
            912
        )
    }

    func testPTYConnectRequestUsesWebSocketAuthAndScope() throws {
        var config = OpenCodeServerConfig()
        config.baseURL = "https://example.com/api"
        config.username = "user"
        config.password = "password"
        let request = try OpenCodeAPIClient(config: config).ptyConnectRequest(
            id: "pty_1",
            directory: "/tmp/project",
            workspaceID: "workspace-1",
            cursor: 27
        )

        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.path, "/api/pty/pty_1/connect")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "directory" })?.value, "/tmp/project")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "workspace" })?.value, "workspace-1")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "cursor" })?.value, "27")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dXNlcjpwYXNzd29yZA==")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-opencode-directory"))
    }

    @MainActor
    func testTerminalStoreKeepsIndependentDirectoryTabs() {
        let store = TerminalStore()
        let first = makePTY(id: "pty_1", title: "Terminal 1", directory: "/tmp/one")
        let second = makePTY(id: "pty_2", title: "Terminal 2", directory: "/tmp/one")
        let other = makePTY(id: "pty_3", title: "Terminal 1", directory: "/tmp/two")

        store.activate(directory: "/tmp/one")
        store.append(first, directory: "/tmp/one")
        store.append(second, directory: "/tmp/one")
        XCTAssertEqual(store.activeTerminal?.id, "pty_2")

        XCTAssertTrue(store.remove(id: "pty_2", directory: "/tmp/one"))
        XCTAssertEqual(store.activeTerminal?.id, "pty_1")

        store.activate(directory: "/tmp/two")
        store.append(other, directory: "/tmp/two")
        XCTAssertEqual(store.activeTerminal?.id, "pty_3")
        XCTAssertEqual(store.workspaces["/tmp/one"]?.terminals.map(\.id), ["pty_1"])
    }

    @MainActor
    func testTerminalStoreReconcilesServerListWithoutSelectingATerminal() {
        let store = TerminalStore()
        let first = makePTY(id: "pty_1", title: "Terminal 1", directory: "/tmp/one")
        let second = makePTY(id: "pty_2", title: "Terminal 2", directory: "/tmp/one")

        store.activate(directory: "/tmp/one")
        store.replaceTerminals([first, second], directory: "/tmp/one")

        XCTAssertEqual(store.activeWorkspace.terminals.map(\.id), ["pty_1", "pty_2"])
        XCTAssertNil(store.activeTerminal)

        store.select(id: second.id, directory: "/tmp/one")
        store.updateCursor(42, id: second.id, directory: "/tmp/one")
        store.replaceTerminals([second], directory: "/tmp/one")

        XCTAssertEqual(store.activeTerminal?.id, "pty_2")
        XCTAssertEqual(store.activeTerminal?.cursor, 42)
    }

    @MainActor
    func testTerminalStorePersistsSharedFontSize() throws {
        let suiteName = "TerminalFeatureTests.fontSize.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialStore = TerminalStore(defaults: defaults)
        XCTAssertEqual(initialStore.fontSize, 12)

        initialStore.setFontSize(9)
        let restoredStore = TerminalStore(defaults: defaults)

        XCTAssertEqual(restoredStore.fontSize, 9)
    }

    @MainActor
    func testTerminalFacadeRoutesPasteTextToActiveRenderer() {
        let directory = "/tmp/one"
        let terminal = makePTY(id: "pty_1", title: "Terminal 1", directory: directory)
        let store = TerminalStore()
        store.activate(directory: directory)
        store.append(terminal, directory: directory)
        let facade = TerminalFacade(
            store: store,
            clientProvider: { nil },
            directoryProvider: { directory }
        )
        var pastedText: String?
        var focusCount = 0

        facade.attachRenderer(
            rendererID: UUID(),
            terminalID: terminal.id,
            output: { _ in },
            input: TerminalFacade.RendererInput(
                insertText: { _ in },
                pasteText: { pastedText = $0 },
                setControlModifier: { _ in },
                setAltModifier: { _ in },
                sendSpecialKey: { _ in },
                focus: { focusCount += 1 },
                dismissKeyboard: {}
            )
        )

        facade.pasteText("printf 'hello'")

        XCTAssertEqual(pastedText, "printf 'hello'")
        XCTAssertEqual(focusCount, 1)
    }

    private func makePTY(id: String, title: String, directory: String) -> OpenCodePTY {
        OpenCodePTY(
            id: id,
            title: title,
            command: "/bin/zsh",
            args: ["-l"],
            cwd: directory,
            status: "running",
            pid: 42
        )
    }
}
