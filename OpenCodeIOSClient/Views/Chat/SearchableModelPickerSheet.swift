import SwiftUI

struct SearchableModelPickerSheet: View {
    let providerGroups: [ChatFacade.ToolbarProviderGroup]
    let reasoningVariants: [ChatFacade.ToolbarReasoningVariant]
    let selectedModelTitle: String
    let selectedReasoningTitle: String?
    let onSelectModel: (OpenCodeModelReference) -> Void
    let onSelectReasoningVariant: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private struct ModelMatch: Identifiable {
        let providerID: String
        let providerName: String
        let model: OpenCodeModel

        var id: String { "\(providerID):\(model.id)" }
    }

    private var matchingResults: [ModelMatch] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results: [ModelMatch] = []
        for group in providerGroups {
            for model in group.models {
                if needle.isEmpty || matches(model, needle: needle) {
                    results.append(ModelMatch(providerID: group.id, providerName: group.name, model: model))
                }
            }
        }
        return results
    }

    private func matches(_ model: OpenCodeModel, needle: String) -> Bool {
        model.name.lowercased().contains(needle) || model.id.lowercased().contains(needle)
    }

    private func isSelectedModel(_ model: OpenCodeModel) -> Bool {
        model.name == selectedModelTitle
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Choose Model"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: String(localized: "Search models")
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Cancel")) {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private var content: some View {
        List {
            if !reasoningVariants.isEmpty {
                Section(String(localized: "Reasoning")) {
                    ForEach(reasoningVariants, id: \.id) { variant in
                        Button {
                            onSelectReasoningVariant(variant.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(variant.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if variant.title == selectedReasoningTitle {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(String(localized: "Models")) {
                if matchingResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(matchingResults) { match in
                        Button {
                            onSelectModel(OpenCodeModelReference(providerID: match.providerID, modelID: match.model.id))
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.model.name)
                                        .font(.body)
                                    Text(match.providerName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isSelectedModel(match.model) {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}