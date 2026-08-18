import Foundation

@MainActor
final class ConnectionCoordinator {
    private let connectionStore: ConnectionStore

    init(connectionStore: ConnectionStore) {
        self.connectionStore = connectionStore
    }

    func connect(
        client: OpenCodeAPIClient,
        isCurrentAttempt: @MainActor () -> Bool = { true },
        applyBootstrap: @MainActor (OpenCodeGlobalBootstrap) async -> Void,
        handleFailure: @MainActor () -> Void
    ) async {
        guard isCurrentAttempt() else { return }
        connectionStore.beginConnecting()
        defer {
            if isCurrentAttempt() {
                connectionStore.finishConnecting()
            }
        }

        do {
            connectionStore.updateConnectionPhase(.checkingServer)
            let health = try await Self.withTimeout(seconds: 8) {
                try await client.health()
            }
            try Task.checkCancellation()
            guard isCurrentAttempt() else { return }

            connectionStore.updateConnectionPhase(.loadingWorkspace)
            let bootstrap = try await Self.withTimeout(seconds: 10) {
                async let projects = client.listProjects()
                async let currentProject = try? client.currentProject()
                return try await OpenCodeGlobalBootstrap(
                    health: health,
                    projects: projects,
                    currentProject: currentProject
                )
            }
            try Task.checkCancellation()
            guard isCurrentAttempt() else { return }
            connectionStore.updateConnectionPhase(.preparingInterface)
            await applyBootstrap(bootstrap)
            try Task.checkCancellation()
            guard isCurrentAttempt() else { return }
            connectionStore.applySuccessfulServerConnection(
                version: bootstrap.health.version,
                healthy: bootstrap.health.healthy
            )
        } catch is CancellationError {
            guard isCurrentAttempt() else { return }
            handleFailure()
            connectionStore.applyConnectionCancellation()
        } catch {
            guard isCurrentAttempt() else { return }
            handleFailure()
            connectionStore.applyConnectionFailure(error)
        }
    }

    func updateConnectionPhase(_ phase: OpenClientConnectionPhase) {
        connectionStore.updateConnectionPhase(phase)
    }

    private nonisolated static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw OpenCodeAPIError.timedOut
            }

            guard let result = try await group.next() else {
                throw OpenCodeAPIError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    func disconnect(
        hasSavedServer: Bool,
        stopActiveWorkspace: @MainActor () -> Void,
        stopEventStream: @MainActor () -> Void,
        resetAppState: @MainActor () -> Void
    ) {
        stopActiveWorkspace()
        stopEventStream()
        connectionStore.resetToDisconnected(showPrompt: hasSavedServer)
        resetAppState()
    }

    func leaveAppleIntelligenceSession(
        preserveDraft: @MainActor () -> Void,
        stopActiveWorkspace: @MainActor () -> Void,
        resetAppState: @MainActor () -> Void,
        clearComposer: @MainActor () -> Void
    ) {
        preserveDraft()
        stopActiveWorkspace()
        connectionStore.resetToDisconnected()
        resetAppState()
        clearComposer()
    }
}
