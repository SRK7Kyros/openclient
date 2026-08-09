import Combine
import Foundation

@MainActor
final class FunAndGamesFacade: ObservableObject {
    private unowned let viewModel: AppViewModel
    private var observations: Set<AnyCancellable> = []

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        Publishers.MergeMany([
            viewModel.funAndGamesStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.modelConfigurationStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.connectionStore.objectWillChange.eraseToAnyPublisher(),
            viewModel.$isShowingFindPlaceModelSheet.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingFindBugLanguageSheet.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isShowingFindBugModelSheet.map { _ in () }.eraseToAnyPublisher(),
        ])
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &observations)
    }

    var showsSection: Bool {
        !viewModel.isBrowsingLocalCache && viewModel.funAndGamesPreferences.showsSection
    }
    var sortedProviders: [OpenCodeProvider] { viewModel.sortedProviders }
    var isLoading: Bool { viewModel.isLoading }
    var pendingFindBugLanguage: FindBugGameLanguage? { viewModel.pendingFindBugLanguage }

    var isShowingFindPlaceModelSheet: Bool {
        get { viewModel.isShowingFindPlaceModelSheet }
        set { viewModel.isShowingFindPlaceModelSheet = newValue }
    }

    var isShowingFindBugLanguageSheet: Bool {
        get { viewModel.isShowingFindBugLanguageSheet }
        set { viewModel.isShowingFindBugLanguageSheet = newValue }
    }

    var isShowingFindBugModelSheet: Bool {
        get { viewModel.isShowingFindBugModelSheet }
        set { viewModel.isShowingFindBugModelSheet = newValue }
    }

    func presentFindPlaceModelSheet() { viewModel.presentFindPlaceModelSheet() }
    func presentFindBugLanguageSheet() { viewModel.presentFindBugLanguageSheet() }
    func selectFindBugLanguage(_ language: FindBugGameLanguage) { viewModel.selectFindBugLanguage(language) }
    func startFindPlaceGame(model: OpenCodeModelReference) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.startFindPlaceGame(model: model)
    }
    func startFindBugGame(model: OpenCodeModelReference) async {
        guard !viewModel.isBrowsingLocalCache else { return }
        await viewModel.startFindBugGame(model: model)
    }
    func cancelFindBugModelSelection() {
        viewModel.isShowingFindBugModelSheet = false
        viewModel.pendingFindBugLanguage = nil
    }
}
