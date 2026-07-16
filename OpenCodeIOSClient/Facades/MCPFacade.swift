import Combine
import Foundation
import SwiftUI

@MainActor
final class MCPFacade: ObservableObject {
    struct Snapshot: Hashable {
        let servers: [OpenCodeMCPServer]
        let connectedServerCount: Int
        let isLoading: Bool
        let togglingServerNames: Set<String>
        let errorMessage: String?
    }

    private let store: MCPStore
    private let clientProvider: () -> OpenCodeAPIClient?
    private let directoryProvider: () -> String?
    private var observation: AnyCancellable?

    init(
        store: MCPStore,
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
        Snapshot(
            servers: store.servers,
            connectedServerCount: store.connectedServerCount,
            isLoading: store.isLoading,
            togglingServerNames: store.togglingServerNames,
            errorMessage: store.errorMessage
        )
    }

    func loadIfNeeded() async {
        guard store.shouldLoadStatus() else { return }
        await reload()
    }

    func reload() async {
        guard let client = clientProvider() else { return }
        store.beginLoading()
        defer { store.finishLoading() }

        do {
            let statuses = try await client.listMCPStatus(directory: directoryProvider())
            withAnimation(opencodeSelectionAnimation) {
                store.applyLoadedStatuses(statuses)
            }
        } catch {
            store.applyLoadError(error)
        }
    }

    func toggleServer(name: String) async {
        guard let client = clientProvider() else { return }
        guard store.beginToggling(name: name) else { return }
        defer { store.finishToggling(name: name) }

        do {
            let directory = directoryProvider()
            if store.isConnected(name: name) {
                try await client.disconnectMCPServer(name: name, directory: directory)
            } else {
                try await client.connectMCPServer(name: name, directory: directory)
            }

            let statuses = try await client.listMCPStatus(directory: directory)
            withAnimation(opencodeSelectionAnimation) {
                store.applyLoadedStatuses(statuses)
            }
        } catch {
            store.applyToggleError(error)
        }
    }

    func reset() {
        store.reset()
    }
}
