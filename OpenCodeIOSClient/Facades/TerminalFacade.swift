import Combine
import Foundation

@MainActor
final class TerminalFacade: ObservableObject {
    enum SpecialKey {
        case escape
        case tab
        case interrupt
        case left
        case down
        case up
        case right
    }

    struct RendererInput {
        let insertText: (String) -> Void
        let pasteText: (String) -> Void
        let setControlModifier: (Bool) -> Void
        let setAltModifier: (Bool) -> Void
        let sendSpecialKey: (SpecialKey) -> Void
        let focus: () -> Void
        let dismissKeyboard: () -> Void
    }

    struct Snapshot: Equatable {
        let directory: String?
        let terminals: [OpenClientTerminalTab]
        let activeTerminalID: String?
        let isLoadingTerminals: Bool
        let isCreatingTerminal: Bool
        let connectionState: OpenClientTerminalConnectionState
        let errorMessage: String?
        let fontSize: Float
        let isControlModifierActive: Bool
        let isAltModifierActive: Bool

        var activeTerminal: OpenClientTerminalTab? {
            guard let activeTerminalID else { return nil }
            return terminals.first { $0.id == activeTerminalID }
        }
    }

    private let store: TerminalStore
    private let clientProvider: () -> OpenCodeAPIClient?
    private let directoryProvider: () -> String?
    private var connection = OpenCodePTYConnection()
    private var observation: AnyCancellable?
    private var connectionTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var rendererOutputHandlers: [UUID: (String) -> Void] = [:]
    private var rendererInput: RendererInput?
    private var attachedTerminalID: String?
    private var attachedRendererID: UUID?
    private var hydratedDirectories: Set<String> = []
    @Published private(set) var isControlModifierActive = false
    @Published private(set) var isAltModifierActive = false

    init(
        store: TerminalStore,
        clientProvider: @escaping () -> OpenCodeAPIClient?,
        directoryProvider: @escaping () -> String?
    ) {
        self.store = store
        self.clientProvider = clientProvider
        self.directoryProvider = directoryProvider
        observation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var snapshot: Snapshot {
        let workspace = store.activeWorkspace
        return Snapshot(
            directory: store.activeDirectory,
            terminals: workspace.terminals,
            activeTerminalID: workspace.activeTerminalID,
            isLoadingTerminals: store.isLoadingTerminals,
            isCreatingTerminal: store.isCreatingTerminal,
            connectionState: store.connectionState,
            errorMessage: store.errorMessage,
            fontSize: store.fontSize,
            isControlModifierActive: isControlModifierActive,
            isAltModifierActive: isAltModifierActive
        )
    }

    nonisolated static func softwareInputBytes(for text: String) -> [UInt8] {
        if text == "\n" || text == "\r" || text == "\r\n" {
            return [0x0D]
        }
        return Array(text.utf8)
    }

    nonisolated static func connectionCursor(
        initialCursor: Int,
        latestCursor: Int?,
        attempt: Int
    ) -> Int {
        attempt == 0 ? initialCursor : latestCursor ?? initialCursor
    }

    func prepareForPresentation() {
        guard let directory = directoryProvider(), !directory.isEmpty else { return }
        if store.activeDirectory != directory {
            detachRenderer()
            store.activate(directory: directory)
        }
        guard !hydratedDirectories.contains(directory) else { return }
        Task { [weak self] in
            await self?.refreshTerminals()
        }
    }

    func refreshTerminals() async {
        guard let client = clientProvider(),
              let directory = directoryProvider(),
              !directory.isEmpty,
              store.beginLoadingTerminals() else { return }
        if store.activeDirectory != directory {
            store.activate(directory: directory)
        }
        defer {
            if store.activeDirectory == directory {
                store.finishLoadingTerminals()
            }
        }
#if DEBUG
        if isTerminalScreenshotFixture {
            hydratedDirectories.insert(directory)
            return
        }
#endif
        do {
            let terminals = try await client.listPTYs(directory: directory)
            guard store.activeDirectory == directory else { return }
            store.replaceTerminals(terminals, directory: directory)
            hydratedDirectories.insert(directory)
        } catch {
            guard store.activeDirectory == directory else { return }
            store.setError(error)
        }
    }

    func createTerminal() {
        guard let client = clientProvider(),
              let directory = directoryProvider(),
              !directory.isEmpty,
              store.beginCreatingTerminal() else { return }
        if store.activeDirectory != directory {
            store.activate(directory: directory)
        }
        let title: String
#if DEBUG
        title = ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_TERMINAL_TITLE"]
            ?? "Terminal \(store.activeWorkspace.terminals.count + 1)"
#else
        title = "Terminal \(store.activeWorkspace.terminals.count + 1)"
#endif

        Task { [weak self] in
            guard let self else { return }
            defer { store.finishCreatingTerminal() }
            do {
                let terminal = try await client.createPTY(title: title, directory: directory)
                store.upsert(terminal, directory: directory)
            } catch {
                store.setError(error)
            }
        }
    }

    func selectTerminal(id: String) {
        guard let directory = store.activeDirectory else { return }
        if store.activeWorkspace.activeTerminalID != id {
            detachRenderer()
        }
        store.select(id: id, directory: directory)
    }

    func closeTerminal(id: String) {
        guard let client = clientProvider(), let directory = store.activeDirectory else { return }
        let wasActive = store.remove(id: id, directory: directory)
        if wasActive {
            detachRenderer()
        }
        Task {
            try? await client.deletePTY(id: id, directory: directory)
        }
    }

    func attachRenderer(
        rendererID: UUID,
        terminalID: String,
        output: @escaping (String) -> Void,
        input: RendererInput
    ) {
        guard let directory = store.activeDirectory,
              store.activeWorkspace.activeTerminalID == terminalID else { return }
#if DEBUG
        if isTerminalScreenshotFixture {
            attachedTerminalID = terminalID
            attachedRendererID = rendererID
            rendererOutputHandlers[rendererID] = output
            rendererInput = input
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.attachedTerminalID == terminalID,
                      self.attachedRendererID == rendererID else { return }
                self.store.setConnectionState(.connected)
                self.rendererOutputHandlers.values.forEach { $0(Self.screenshotFixtureTranscript) }
            }
            return
        }
#endif
        if attachedTerminalID == terminalID, attachedRendererID == rendererID {
            rendererOutputHandlers[rendererID] = output
            rendererInput = input
            return
        }

        let preservesSameTerminalRenderers = attachedTerminalID == terminalID
        let previousConnection = connection
        disconnectRendererResources(preservingRendererOutputs: preservesSameTerminalRenderers)
        Task {
            await previousConnection.disconnect()
        }
        attachedTerminalID = terminalID
        attachedRendererID = rendererID
        rendererOutputHandlers[rendererID] = output
        rendererInput = input
        // A new Ghostty surface has no screen state. Replay the server buffer so
        // terminal contents, modes, and cursor position are reconstructed.
        let initialCursor = 0
        let rendererConnection = connection
        connectionTask = Task { [weak self] in
            await self?.runConnection(
                terminalID: terminalID,
                rendererID: rendererID,
                directory: directory,
                initialCursor: initialCursor,
                connection: rendererConnection
            )
        }
    }

    func detachRenderer(terminalID: String? = nil, rendererID: UUID? = nil) {
        if let terminalID, attachedTerminalID != terminalID { return }
        if let rendererID, attachedRendererID != rendererID { return }
        let detachedConnection = connection
        disconnectRendererResources()
        if isControlModifierActive {
            isControlModifierActive = false
        }
        if isAltModifierActive {
            isAltModifierActive = false
        }
        if store.connectionState != .disconnected {
            store.setConnectionState(.disconnected)
        }
        Task {
            await detachedConnection.disconnect()
        }
    }

    @discardableResult
    func send(_ bytes: [UInt8], terminalID: String, rendererID: UUID) -> Bool {
        guard attachedTerminalID == terminalID,
              rendererOutputHandlers[rendererID] != nil else { return false }
        let activeConnection = connection
        Task { [weak self] in
            guard let self else { return }
            do {
                try await activeConnection.send(bytes)
            } catch where error is CancellationError {
            } catch {
                store.setError(error)
            }
        }
        return true
    }

    func insertText(_ text: String) {
        rendererInput?.insertText(text)
        rendererInput?.focus()
    }

    func pasteText(_ text: String) {
        rendererInput?.pasteText(text)
        rendererInput?.focus()
    }

    func sendSpecialKey(_ key: SpecialKey) {
        rendererInput?.sendSpecialKey(key)
        rendererInput?.focus()
    }

    func toggleControlModifier() {
        isControlModifierActive.toggle()
        rendererInput?.setControlModifier(isControlModifierActive)
        rendererInput?.focus()
    }

    func toggleAltModifier() {
        isAltModifierActive.toggle()
        rendererInput?.setAltModifier(isAltModifierActive)
        rendererInput?.focus()
    }

    func syncModifierState(control: Bool, alt: Bool) {
        isControlModifierActive = control
        isAltModifierActive = alt
    }

    func dismissKeyboard() {
        rendererInput?.dismissKeyboard()
    }

    func setFontSize(_ fontSize: Float) {
        store.setFontSize(fontSize)
    }

    func resize(terminalID: String, rows: Int, columns: Int) {
#if DEBUG
        if isTerminalScreenshotFixture {
            return
        }
#endif
        guard rows > 0, columns > 0,
              let directory = store.activeDirectory,
              store.activeWorkspace.activeTerminalID == terminalID else { return }
        let terminal = store.activeWorkspace.terminals.first { $0.id == terminalID }
        guard terminal?.rows != rows || terminal?.columns != columns else { return }
        store.updateSize(rows: rows, columns: columns, id: terminalID, directory: directory)

        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self, let client = clientProvider() else { return }
            do {
                let info = try await client.updatePTY(
                    id: terminalID,
                    rows: rows,
                    columns: columns,
                    directory: directory
                )
                store.update(info: info, directory: directory)
            } catch where error is CancellationError {
            } catch {
                store.setError(error)
            }
        }
    }

    @discardableResult
    func consume(_ event: OpenCodeManagedEvent) -> Bool {
        switch event.typed {
        case let .ptyCreated(info):
            store.upsert(info, directory: event.directory)
            return true
        case let .ptyUpdated(info):
            store.update(info: info, directory: event.directory)
            return true
        case let .ptyExited(id, _):
            let removedActive = store.remove(id: id, directory: event.directory)
            if removedActive {
                detachRenderer()
            }
            return true
        case let .ptyDeleted(id):
            let removedActive = store.remove(id: id, directory: event.directory)
            if removedActive {
                detachRenderer()
            }
            return true
        default:
            return false
        }
    }

    private func runConnection(
        terminalID: String,
        rendererID: UUID,
        directory: String,
        initialCursor: Int,
        connection: OpenCodePTYConnection
    ) async {
        guard let client = clientProvider() else { return }
        var attempt = 0

        while !Task.isCancelled,
              attachedTerminalID == terminalID,
              attachedRendererID == rendererID,
              store.activeDirectory == directory {
            do {
                store.setConnectionState(attempt == 0 ? .connecting : .reconnecting)
                let cursor = Self.connectionCursor(
                    initialCursor: initialCursor,
                    latestCursor: store.workspaces[directory]?.terminals.first(where: { $0.id == terminalID })?.cursor,
                    attempt: attempt
                )
                let request = try client.ptyConnectRequest(id: terminalID, directory: directory, cursor: cursor)
                try await connection.run(request: request, initialCursor: cursor) { [weak self] event in
                    await MainActor.run {
                        guard let self,
                              self.attachedTerminalID == terminalID,
                              self.attachedRendererID == rendererID else { return }
                        switch event {
                        case .connected:
                            self.store.setConnectionState(.connected)
                        case let .output(text, nextCursor):
                            self.store.updateCursor(nextCursor, id: terminalID, directory: directory)
                            self.rendererOutputHandlers.values.forEach { $0(text) }
                        case let .cursor(nextCursor):
                            self.store.updateCursor(nextCursor, id: terminalID, directory: directory)
                        }
                    }
                }
            } catch where error is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      attachedTerminalID == terminalID,
                      attachedRendererID == rendererID else { return }
                do {
                    _ = try await client.getPTY(id: terminalID, directory: directory)
                } catch let OpenCodeAPIError.httpError(code, _) where code == 404 {
                    await replaceStaleTerminal(id: terminalID, directory: directory, client: client)
                    return
                } catch {
                    store.setError(error)
                }

                attempt = min(attempt + 1, 4)
                store.setConnectionState(.reconnecting)
                let delay = 250 * Int(pow(2.0, Double(attempt - 1)))
                try? await Task.sleep(for: .milliseconds(min(delay, 4_000)))
            }
        }
    }

    private func disconnectRendererResources(preservingRendererOutputs: Bool = false) {
        attachedTerminalID = nil
        attachedRendererID = nil
        if !preservingRendererOutputs {
            rendererOutputHandlers.removeAll()
        }
        rendererInput = nil
        connectionTask?.cancel()
        connectionTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        connection = OpenCodePTYConnection()
    }

    private func replaceStaleTerminal(id: String, directory: String, client: OpenCodeAPIClient) async {
        guard let old = store.workspaces[directory]?.terminals.first(where: { $0.id == id }) else { return }
        do {
            let replacement = try await client.createPTY(title: old.title, directory: directory)
            store.replace(id: id, with: replacement, directory: directory)
        } catch {
            store.setError(error)
        }
    }

#if DEBUG
    private var isTerminalScreenshotFixture: Bool {
        let scene = ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"]
        return scene == "terminal" || scene == "terminal-showcase"
    }

    private static let screenshotFixtureTranscript: String = {
        let progress = (1 ... 145).map { index in
            let percent = min(99, 24 + index / 2)
            return "\u{001B}[90m  compiling OpenClient module \(String(format: "%03d", index))  \(percent)%\u{001B}[0m"
        }
        let summary = [
            "",
            "\u{001B}[1;36mOpenClient 1.0.13 · Release validation\u{001B}[0m",
            "",
            "\u{001B}[32m✓\u{001B}[0m Swift release build",
            "\u{001B}[32m✓\u{001B}[0m Plugin bridge tools",
            "\u{001B}[32m✓\u{001B}[0m Browser automation",
            "\u{001B}[32m✓\u{001B}[0m Visual tool renderers",
            "\u{001B}[32m✓\u{001B}[0m Unit and UI tests",
            "",
            "\u{001B}[1;35mReady for TestFlight\u{001B}[0m  \u{001B}[90m1.0.13 (15)\u{001B}[0m",
            "",
            "\u{001B}[1;34mopenclient\u{001B}[0m \u{001B}[90m…/openclient\u{001B}[0m % ",
        ]
        return "\u{001B}[2J\u{001B}[H" + (progress + summary).joined(separator: "\r\n")
    }()
#endif
}
