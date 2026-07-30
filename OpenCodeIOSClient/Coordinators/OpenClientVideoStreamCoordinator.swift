import Foundation

@MainActor
final class OpenClientVideoStreamCoordinator {
    private let bridgeStore: OpenClientBridgeStore
    private let transport: any OpenClientVideoStreamTransport

    init(
        bridgeStore: OpenClientBridgeStore,
        transport: any OpenClientVideoStreamTransport = OpenClientVideoStreamClient()
    ) {
        self.bridgeStore = bridgeStore
        self.transport = transport
    }

    func start(payload: OpenClientVisualVideoPayload) async throws -> OpenClientVideoStream {
        guard case .connected = bridgeStore.phase,
              let endpoint = bridgeStore.endpoint else {
            throw OpenClientVideoStreamError.unavailable
        }
        return try await transport.start(payload: payload, endpoint: endpoint)
    }

    func stop(stream: OpenClientVideoStream) async {
        guard let endpoint = bridgeStore.endpoint else { return }
        try? await transport.stop(stream: stream, endpoint: endpoint)
    }
}
