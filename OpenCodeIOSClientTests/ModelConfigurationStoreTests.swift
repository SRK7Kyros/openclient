import XCTest
@testable import OpenClient

@MainActor
final class ModelConfigurationStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "opencode.modelVisibility.v1")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "opencode.modelVisibility.v1")
        super.tearDown()
    }

    func testApplyProviderStateUsesOnlyConnectedProvidersForSelection() {
        let store = ModelConfigurationStore()
        let openAI = provider(id: "openai", name: "OpenAI")
        let anthropic = provider(id: "anthropic", name: "Anthropic")

        store.applyProviderState(OpenCodeProviderListResponse(all: [openAI, anthropic], connected: ["openai"], default: ["openai": "gpt-5"]))

        XCTAssertEqual(store.allProviders.map(\.id).sorted(), ["anthropic", "openai"])
        XCTAssertEqual(store.availableProviders.map(\.id), ["openai"])
        XCTAssertEqual(store.addableProviders.map(\.id).sorted(), ["anthropic", "openai"])
        XCTAssertEqual(store.defaultModelReference(), OpenCodeModelReference(providerID: "openai", modelID: "gpt-5"))
    }

    func testModelVisibilityPreferenceOverridesDefaultVisibility() {
        let store = ModelConfigurationStore()
        let provider = provider(id: "openai", name: "OpenAI", releaseDate: "2020-01-01")
        store.applyProviderState(OpenCodeProviderListResponse(all: [provider], connected: ["openai"], default: [:]))
        let reference = OpenCodeModelReference(providerID: "openai", modelID: "gpt-5")

        XCTAssertFalse(store.isModelVisible(reference))

        store.setModelVisibility(reference, isVisible: true)

        XCTAssertTrue(store.isModelVisible(reference))

        store.setModelVisibility(reference, isVisible: false)

        XCTAssertFalse(store.isModelVisible(reference))
    }

    func testProviderVisibilityTogglesEveryModel() {
        let store = ModelConfigurationStore()
        let provider = OpenCodeProvider(
            id: "openai",
            name: "OpenAI",
            models: [
                "gpt-5": model(id: "gpt-5", providerID: "openai"),
                "gpt-5-mini": model(id: "gpt-5-mini", providerID: "openai"),
            ]
        )
        store.applyProviderState(OpenCodeProviderListResponse(all: [provider], connected: ["openai"], default: [:]))

        store.setProviderVisibility(provider, isVisible: false)

        XCTAssertFalse(store.isProviderFullyVisible(provider))
        XCTAssertTrue(store.visibleModels(for: provider).isEmpty)

        store.setProviderVisibility(provider, isVisible: true)

        XCTAssertTrue(store.isProviderFullyVisible(provider))
        XCTAssertEqual(store.visibleModels(for: provider).count, 2)
    }

    func testConfigBackedProviderIsNotTreatedAsCustomProvider() {
        let store = ModelConfigurationStore()
        let provider = provider(id: "github-copilot", name: "GitHub Copilot", source: "config")

        XCTAssertFalse(store.isConfigCustomProvider(provider))
        XCTAssertEqual(store.sourceTitle(for: provider), "Config")
    }

    func testVisibleModelsAreCappedForLargeConnectedCatalogs() {
        let store = ModelConfigurationStore()
        let models = Dictionary(uniqueKeysWithValues: (0 ..< 140).map { index in
            let id = String(format: "model-%03d", index)
            return (id, model(id: id, providerID: "openrouter"))
        })
        let provider = OpenCodeProvider(id: "openrouter", name: "OpenRouter", models: models)

        store.applyProviderState(OpenCodeProviderListResponse(all: [provider], connected: ["openrouter"], default: [:]))

        let visibleModels = store.visibleModels(for: provider)
        XCTAssertEqual(visibleModels.count, ModelConfigurationStore.visibleModelLimitPerProvider)
        XCTAssertEqual(visibleModels.first?.id, "model-000")
        XCTAssertEqual(visibleModels.last?.id, "model-079")
    }

    private func provider(id: String, name: String, releaseDate: String? = nil, source: String? = nil) -> OpenCodeProvider {
        OpenCodeProvider(id: id, name: name, models: ["gpt-5": model(id: "gpt-5", providerID: id, releaseDate: releaseDate)], source: source)
    }

    private func model(id: String, providerID: String, releaseDate: String? = nil) -> OpenCodeModel {
        OpenCodeModel(
            id: id,
            providerID: providerID,
            name: id,
            capabilities: OpenCodeModelCapabilities(reasoning: false),
            releaseDate: releaseDate
        )
    }
}
