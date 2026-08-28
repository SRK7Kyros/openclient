import SwiftUI

struct ModelToolbarMenu: View {
    let modelTitle: String
    let providerGroups: [ChatFacade.ToolbarProviderGroup]
    let reasoningVariants: [ChatFacade.ToolbarReasoningVariant]
    let reasoningTitle: String
    let glassNamespace: Namespace.ID
    let onSelectModel: (OpenCodeModelReference) -> Void
    let onSelectReasoningVariant: (String) -> Void

    @State private var showingModelPicker = false

    var body: some View {
        Button {
            showingModelPicker = true
        } label: {
            menuLabel
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opencodeToolbarGlassID("model-toolbar", in: glassNamespace)
        .accessibilityLabel(accessibilityValue)
        .accessibilityIdentifier("chat.toolbar.model")
        .sheet(isPresented: $showingModelPicker) {
            SearchableModelPickerSheet(
                providerGroups: providerGroups,
                reasoningVariants: reasoningVariants,
                selectedModelTitle: modelTitle,
                selectedReasoningTitle: reasoningSubtitle,
                onSelectModel: onSelectModel,
                onSelectReasoningVariant: onSelectReasoningVariant
            )
        }
    }

    private var menuLabel: some View {
        HStack(spacing: 6) {
            if let reasoningSubtitle {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(modelTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(reasoningSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(modelTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minWidth: 150, minHeight: 36, alignment: .trailing)
    }

    private var reasoningSubtitle: String? {
        guard !reasoningVariants.isEmpty else { return nil }
        return reasoningTitle
    }

    private var accessibilityValue: String {
        guard let reasoningSubtitle else { return modelTitle }
        return "\(modelTitle), \(reasoningSubtitle)"
    }
}