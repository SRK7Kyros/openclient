import SwiftUI

enum TodoStatusPresentation {
    static func title(for status: String) -> LocalizedStringResource? {
        switch status {
        case "pending":
            LocalizedStringResource(
                "todo.status.pending",
                defaultValue: "Pending",
                comment: "Status of a todo item that has not started."
            )
        case "in_progress":
            LocalizedStringResource(
                "todo.status.in_progress",
                defaultValue: "In Progress",
                comment: "Status of a todo item that is currently being worked on."
            )
        case "completed":
            LocalizedStringResource(
                "todo.status.completed",
                defaultValue: "Completed",
                comment: "Status of a completed todo item."
            )
        case "cancelled":
            LocalizedStringResource(
                "todo.status.cancelled",
                defaultValue: "Cancelled",
                comment: "Status of a cancelled todo item."
            )
        default:
            nil
        }
    }
}

struct TodoStatusLabel: View {
    let status: String

    var body: some View {
        if let title = TodoStatusPresentation.title(for: status) {
            Text(title)
        } else {
            Text(verbatim: status.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }
}

struct TodoCard: View {
    let todo: OpenCodeTodo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.content)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                TodoStatusLabel(status: todo.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .frame(minHeight: 78, alignment: .leading)
        .opencodeGlassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: todo.isInProgress ? 1.2 : 0.8)
        }
        .animation(opencodeSelectionAnimation, value: todo.status)
    }

    private var iconName: String {
        if todo.isComplete { return "checkmark.circle.fill" }
        if todo.isInProgress { return "clock.badge" }
        return "circle"
    }

    private var iconColor: Color {
        if todo.isComplete { return .green }
        if todo.isInProgress { return .blue }
        return .secondary
    }

    private var borderColor: Color {
        if todo.isInProgress { return .blue.opacity(0.35) }
        if todo.isComplete { return .green.opacity(0.25) }
        return Color.black.opacity(0.06)
    }
}
