import SwiftUI

struct ModelToolbarMenu: View {
    let modelTitle: String
    let providerGroups: [ChatFacade.ToolbarProviderGroup]
    let reasoningVariants: [ChatFacade.ToolbarReasoningVariant]
    let reasoningTitle: String
    let glassNamespace: Namespace.ID
    let onSelectModel: (OpenCodeModelReference) -> Void
    let onSelectReasoningVariant: (String) -> Void

    var body: some View {
        StablePickerMenu(
            elements: menuElements,
            accessibilityLabel: "Model",
            accessibilityValue: modelTitle,
            accessibilityIdentifier: "chat.toolbar.model",
            onSelect: select
        ) {
            Group {
                if let reasoningSubtitle {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(modelTitle)
                            .font(.caption)
                        Text(reasoningSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(modelTitle)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 72, alignment: .trailing)
            .opencodeToolbarGlassID("model-toolbar", in: glassNamespace)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var reasoningSubtitle: String? {
        guard !reasoningVariants.isEmpty else { return nil }
        return reasoningTitle
    }

    private var menuElements: [StablePickerMenuElement] {
        var elements = [StablePickerMenuElement.submenu(
            id: "models",
            title: "Model",
            children: providerGroups.map { provider in
                .submenu(
                    id: "provider:\(provider.id)",
                    title: provider.name,
                    children: provider.models.map { model in
                        .action(
                            id: modelActionID(providerID: provider.id, modelID: model.id),
                            title: model.name,
                            systemImage: nil,
                            isSelected: model.name == modelTitle
                        )
                    }
                )
            }
        )]

        if !reasoningVariants.isEmpty {
            elements.append(.submenu(
                id: "reasoning",
                title: "Reasoning",
                children: reasoningVariants.map { variant in
                    .action(
                        id: reasoningActionID(variant.id),
                        title: variant.title,
                        systemImage: nil,
                        isSelected: variant.title == reasoningTitle
                    )
                }
            ))
        }
        return elements
    }

    private func select(_ actionID: String) {
        if actionID.hasPrefix("reasoning:") {
            let variantID = String(actionID.dropFirst("reasoning:".count))
            onSelectReasoningVariant(variantID)
            return
        }

        for provider in providerGroups {
            if let model = provider.models.first(where: {
                modelActionID(providerID: provider.id, modelID: $0.id) == actionID
            }) {
                onSelectModel(OpenCodeModelReference(providerID: provider.id, modelID: model.id))
                return
            }
        }
    }

    private func modelActionID(providerID: String, modelID: String) -> String {
        "model:\(providerID):\(modelID)"
    }

    private func reasoningActionID(_ variantID: String) -> String {
        "reasoning:\(variantID)"
    }
}
