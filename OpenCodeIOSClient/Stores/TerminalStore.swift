import Combine
import Foundation

struct OpenClientTerminalTab: Hashable, Identifiable, Sendable {
    var info: OpenCodePTY
    var cursor: Int
    var rows: Int?
    var columns: Int?

    var id: String { info.id }
    var title: String { info.title }
}

struct OpenClientTerminalWorkspaceState: Hashable, Sendable {
    var terminals: [OpenClientTerminalTab] = []
    var activeTerminalID: String?
}

enum OpenClientTerminalConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

@MainActor
final class TerminalStore: ObservableObject {
    static let defaultFontSize: Float = 12

    @Published private(set) var activeDirectory: String?
    @Published private(set) var workspaces: [String: OpenClientTerminalWorkspaceState]
    @Published private(set) var isLoadingTerminals: Bool
    @Published private(set) var isCreatingTerminal: Bool
    @Published private(set) var connectionState: OpenClientTerminalConnectionState
    @Published private(set) var errorMessage: String?
    @Published private(set) var fontSize: Float
    private let defaults: UserDefaults

    init(
        activeDirectory: String? = nil,
        workspaces: [String: OpenClientTerminalWorkspaceState] = [:],
        isLoadingTerminals: Bool = false,
        isCreatingTerminal: Bool = false,
        connectionState: OpenClientTerminalConnectionState = .disconnected,
        errorMessage: String? = nil,
        fontSize: Float? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.activeDirectory = activeDirectory
        self.workspaces = workspaces
        self.isLoadingTerminals = isLoadingTerminals
        self.isCreatingTerminal = isCreatingTerminal
        self.connectionState = connectionState
        self.errorMessage = errorMessage
        self.defaults = defaults
        let storedFontSize = (defaults.object(forKey: OpenClientStorageKey.terminalFontSize) as? NSNumber)?.floatValue
        self.fontSize = min(max(fontSize ?? storedFontSize ?? Self.defaultFontSize, 4), 64)
    }

    var activeWorkspace: OpenClientTerminalWorkspaceState {
        guard let activeDirectory else { return OpenClientTerminalWorkspaceState() }
        return workspaces[activeDirectory] ?? OpenClientTerminalWorkspaceState()
    }

    var activeTerminal: OpenClientTerminalTab? {
        let workspace = activeWorkspace
        guard let activeTerminalID = workspace.activeTerminalID else { return nil }
        return workspace.terminals.first { $0.id == activeTerminalID }
    }

    func activate(directory: String) {
        guard !directory.isEmpty else { return }
        if workspaces[directory] == nil {
            workspaces[directory] = OpenClientTerminalWorkspaceState()
        }
        activeDirectory = directory
        errorMessage = nil
        isLoadingTerminals = false
        connectionState = .disconnected
    }

    func beginCreatingTerminal() -> Bool {
        guard !isCreatingTerminal else { return false }
        isCreatingTerminal = true
        errorMessage = nil
        return true
    }

    func beginLoadingTerminals() -> Bool {
        guard !isLoadingTerminals else { return false }
        isLoadingTerminals = true
        errorMessage = nil
        return true
    }

    func finishLoadingTerminals() {
        isLoadingTerminals = false
    }

    func finishCreatingTerminal() {
        isCreatingTerminal = false
    }

    func append(_ info: OpenCodePTY, directory: String) {
        var workspace = workspaces[directory] ?? OpenClientTerminalWorkspaceState()
        if let index = workspace.terminals.firstIndex(where: { $0.id == info.id }) {
            workspace.terminals[index].info = info
        } else {
            workspace.terminals.append(OpenClientTerminalTab(info: info, cursor: 0))
        }
        workspace.activeTerminalID = info.id
        workspaces[directory] = workspace
        errorMessage = nil
    }

    func upsert(_ info: OpenCodePTY, directory: String) {
        var workspace = workspaces[directory] ?? OpenClientTerminalWorkspaceState()
        if let index = workspace.terminals.firstIndex(where: { $0.id == info.id }) {
            workspace.terminals[index].info = info
        } else {
            workspace.terminals.append(OpenClientTerminalTab(info: info, cursor: 0))
        }
        workspaces[directory] = workspace
        errorMessage = nil
    }

    func replaceTerminals(_ infos: [OpenCodePTY], directory: String) {
        let existing = workspaces[directory] ?? OpenClientTerminalWorkspaceState()
        let existingByID = Dictionary(uniqueKeysWithValues: existing.terminals.map { ($0.id, $0) })
        let terminals = infos.map { info in
            guard var terminal = existingByID[info.id] else {
                return OpenClientTerminalTab(info: info, cursor: 0)
            }
            terminal.info = info
            return terminal
        }
        let activeTerminalID = existing.activeTerminalID.flatMap { activeID in
            terminals.contains(where: { $0.id == activeID }) ? activeID : nil
        }
        workspaces[directory] = OpenClientTerminalWorkspaceState(
            terminals: terminals,
            activeTerminalID: activeTerminalID
        )
        errorMessage = nil
    }

    func select(id: String, directory: String) {
        guard var workspace = workspaces[directory],
              workspace.terminals.contains(where: { $0.id == id }) else { return }
        let changedSelection = workspace.activeTerminalID != id
        workspace.activeTerminalID = id
        workspaces[directory] = workspace
        errorMessage = nil
        if changedSelection {
            connectionState = .disconnected
        }
    }

    @discardableResult
    func remove(id: String, directory: String) -> Bool {
        guard var workspace = workspaces[directory],
              let index = workspace.terminals.firstIndex(where: { $0.id == id }) else { return false }
        let wasActive = workspace.activeTerminalID == id
        workspace.terminals.remove(at: index)
        if wasActive {
            let nextIndex = min(max(index - 1, 0), max(workspace.terminals.count - 1, 0))
            workspace.activeTerminalID = workspace.terminals.isEmpty ? nil : workspace.terminals[nextIndex].id
        }
        workspaces[directory] = workspace
        if wasActive {
            connectionState = .disconnected
        }
        return wasActive
    }

    func replace(id: String, with info: OpenCodePTY, directory: String) {
        guard var workspace = workspaces[directory],
              let index = workspace.terminals.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = workspace.activeTerminalID == id
        workspace.terminals[index] = OpenClientTerminalTab(info: info, cursor: 0)
        if wasActive {
            workspace.activeTerminalID = info.id
        }
        workspaces[directory] = workspace
    }

    func update(info: OpenCodePTY, directory: String) {
        guard var workspace = workspaces[directory],
              let index = workspace.terminals.firstIndex(where: { $0.id == info.id }) else { return }
        workspace.terminals[index].info = info
        workspaces[directory] = workspace
    }

    func updateCursor(_ cursor: Int, id: String, directory: String) {
        guard var workspace = workspaces[directory],
              let index = workspace.terminals.firstIndex(where: { $0.id == id }) else { return }
        workspace.terminals[index].cursor = cursor
        workspaces[directory] = workspace
    }

    func updateSize(rows: Int, columns: Int, id: String, directory: String) {
        guard var workspace = workspaces[directory],
              let index = workspace.terminals.firstIndex(where: { $0.id == id }) else { return }
        workspace.terminals[index].rows = rows
        workspace.terminals[index].columns = columns
        workspaces[directory] = workspace
    }

    func setConnectionState(_ state: OpenClientTerminalConnectionState) {
        connectionState = state
        if state == .connected {
            errorMessage = nil
        }
    }

    func setError(_ error: Error) {
        errorMessage = error.localizedDescription
        connectionState = .disconnected
    }

    func setFontSize(_ fontSize: Float) {
        let clamped = min(max(fontSize, 4), 64)
        guard self.fontSize != clamped else { return }
        self.fontSize = clamped
        defaults.set(clamped, forKey: OpenClientStorageKey.terminalFontSize)
    }
}
