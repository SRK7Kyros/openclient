import Combine
import Foundation

struct OpenClientBridgeSnapshot: Equatable {
    let phase: OpenClientBridgePhase
    let endpoint: URL?
    let errorMessage: String?
    let clientID: String
    let displayName: String
    let appVersion: String

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    var showsToolbarButton: Bool { isConnected }

    var isBusy: Bool {
        switch phase {
        case .searching, .connecting:
            return true
        case .idle, .connected:
            return false
        }
    }

    var statusTitle: String {
        switch phase {
        case .idle:
            return String(localized: "Disconnected")
        case .searching:
            return String(localized: "Searching")
        case .connecting:
            return String(localized: "Connecting")
        case .connected:
            return String(localized: "Connected")
        }
    }

    var statusDetail: String {
        switch phase {
        case .idle:
            return errorMessage ?? String(localized: "No plugin bridge connection is active.")
        case .searching:
            return String(localized: "Scanning the OpenCode host on ports 4070 through 4090.")
        case .connecting(let port):
            return String(localized: "Opening the plugin bridge on port \(port).")
        case .connected(let port):
            return String(localized: "Device tools are available through port \(port).")
        }
    }

    var toolbarSystemImage: String {
        isConnected ? "link.circle.fill" : "link.circle"
    }
}

@MainActor
final class OpenClientBridgeFacade: ObservableObject {
    private let store: OpenClientBridgeStore
    private let forceConnectAction: @MainActor () -> Void
    private var observation: AnyCancellable?

    init(
        store: OpenClientBridgeStore,
        forceConnect: @escaping @MainActor () -> Void
    ) {
        self.store = store
        forceConnectAction = forceConnect
        observation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var snapshot: OpenClientBridgeSnapshot {
        OpenClientBridgeSnapshot(
            phase: store.phase,
            endpoint: store.endpoint?.webSocketURL,
            errorMessage: store.errorMessage,
            clientID: store.clientID,
            displayName: store.displayName,
            appVersion: store.appVersion
        )
    }

    func forceConnect() {
        forceConnectAction()
    }
}
