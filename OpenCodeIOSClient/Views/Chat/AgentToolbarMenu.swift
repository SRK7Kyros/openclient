import SwiftUI

struct AgentToolbarMenu: View {
    let title: String
    let agents: [OpenCodeAgent]
    let glassNamespace: Namespace.ID
    let onSelectAgent: (String) -> Void

    var body: some View {
        StablePickerMenu(
            elements: agents.map { agent in
                .action(
                    id: agent.name,
                    title: agent.name.capitalized,
                    systemImage: "person.crop.circle",
                    isSelected: agent.name.caseInsensitiveCompare(title) == .orderedSame
                )
            },
            accessibilityLabel: "Agent",
            accessibilityValue: title,
            accessibilityIdentifier: "chat.toolbar.agent",
            onSelect: onSelectAgent
        ) {
            Text(title.capitalized)
                .font(.caption)
                .padding(.horizontal, 6)
                .frame(minWidth: 44, minHeight: 44)
                .opencodeToolbarGlassID("agent-toolbar", in: glassNamespace)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
