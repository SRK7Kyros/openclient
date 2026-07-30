import Foundation

@MainActor
final class OpenClientImageContentCoordinator {
    private let bridgeStore: OpenClientBridgeStore
    private let transport: any OpenClientImageContentTransport

    init(
        bridgeStore: OpenClientBridgeStore,
        transport: any OpenClientImageContentTransport = OpenClientImageContentClient()
    ) {
        self.bridgeStore = bridgeStore
        self.transport = transport
    }

    func load(payload: OpenClientVisualImagePayload) async throws -> OpenClientLoadedImage {
        guard case .connected = bridgeStore.phase,
              let endpoint = bridgeStore.endpoint else {
            throw OpenClientImageContentError.unavailable
        }
        return try await transport.load(payload: payload, endpoint: endpoint)
    }
}
