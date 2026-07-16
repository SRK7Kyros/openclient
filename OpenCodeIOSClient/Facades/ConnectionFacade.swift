import Combine
import Foundation

@MainActor
final class ConnectionFacade: ObservableObject {
    private unowned let viewModel: AppViewModel
    private var observations: Set<AnyCancellable> = []
    private var activeDirectoryObservation: AnyCancellable?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        Publishers.MergeMany([
            viewModel.connectionStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.$config.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingConnectionOverlay.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingAppleIntelligenceFolderPicker.map { _ in () }.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &observations)

        bindActiveDirectoryStore(viewModel.directoryStoreRegistry.activeStore)
        viewModel.directoryStoreRegistry.$activeStore
            .dropFirst()
            .sink { [weak self] store in
                self?.bindActiveDirectoryStore(store)
                self?.objectWillChange.send()
            }
            .store(in: &observations)
    }

    var config: OpenCodeServerConfig {
        get { viewModel.config }
        set { viewModel.config = newValue }
    }

    var isConnected: Bool { viewModel.isConnected }
    var isShowingConnectionOverlay: Bool { viewModel.isShowingConnectionOverlay }
    var connectionPhase: OpenClientConnectionPhase { viewModel.connectionPhase }
    var isUsingAppleIntelligence: Bool { viewModel.isUsingAppleIntelligence }
    var selectedSessionID: String? { viewModel.selectedSession?.id }
    var recentServerConfigs: [OpenCodeServerConfig] { viewModel.recentServerConfigs }
    var errorMessage: String? { viewModel.errorMessage }
    var isLoading: Bool { viewModel.isLoading }
    var isEditingSavedServer: Bool { viewModel.isEditingSavedServer }
    var canSaveEditedServer: Bool { viewModel.canSaveEditedServer }
    var canTryAppleIntelligence: Bool { viewModel.canTryAppleIntelligence }
    var appleIntelligenceAvailabilitySummary: String? { viewModel.appleIntelligenceAvailabilitySummary }

    var isShowingAppleIntelligenceFolderPicker: Bool {
        get { viewModel.isShowingAppleIntelligenceFolderPicker }
        set { viewModel.isShowingAppleIntelligenceFolderPicker = newValue }
    }

    func startConnection() {
        viewModel.startConnection()
    }

    func startConnection(to serverConfig: OpenCodeServerConfig) {
        viewModel.startConnection(to: serverConfig)
    }

    func startConnectionFromEditor() {
        viewModel.startConnectionFromEditor()
    }

    func cancelConnectionAttempt() {
        viewModel.cancelConnectionAttempt()
    }

    func presentAddServerSheet() {
        viewModel.presentAddServerSheet()
    }

    func prepareToEditRecentServer(_ serverConfig: OpenCodeServerConfig) {
        viewModel.prepareToEditRecentServer(serverConfig)
    }

    func removeRecentServer(_ serverConfig: OpenCodeServerConfig) {
        viewModel.removeRecentServer(serverConfig)
    }

    func saveEditedServer() {
        viewModel.saveEditedServer()
    }

    func presentAppleIntelligenceFolderPicker() {
        viewModel.presentAppleIntelligenceFolderPicker()
    }

    func createAppleIntelligenceWorkspace(from directoryURL: URL) async {
        await viewModel.createAppleIntelligenceWorkspace(from: directoryURL)
    }

    func leaveAppleIntelligenceSession() {
        viewModel.leaveAppleIntelligenceSession()
    }

    func disconnect() {
        viewModel.disconnect()
    }

    private func bindActiveDirectoryStore(_ store: DirectoryStore) {
        activeDirectoryObservation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}
