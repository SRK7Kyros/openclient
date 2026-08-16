import SwiftUI

struct SessionRow: View, Equatable {
    enum Style: Equatable {
        case regular
        case compact
    }

    let session: OpenCodeSession
    var isSelected = false
    var showsPinnedBadge = false
    var workspaceOverline: String?
    var style: Style = .regular
    var preview: SessionPreview?
    var isBusy = false
    var hasLiveActivity = false
    var hasDraft = false
    var hasPermissionRequest = false
    var displayTitle: String? = nil
    var shimmersTitle = false

    nonisolated static func == (lhs: SessionRow, rhs: SessionRow) -> Bool {
        lhs.session == rhs.session
            && lhs.isSelected == rhs.isSelected
            && lhs.showsPinnedBadge == rhs.showsPinnedBadge
            && lhs.workspaceOverline == rhs.workspaceOverline
            && lhs.style == rhs.style
            && lhs.preview == rhs.preview
            && lhs.isBusy == rhs.isBusy
            && lhs.hasLiveActivity == rhs.hasLiveActivity
            && lhs.hasDraft == rhs.hasDraft
            && lhs.hasPermissionRequest == rhs.hasPermissionRequest
            && lhs.displayTitle == rhs.displayTitle
            && lhs.shimmersTitle == rhs.shimmersTitle
    }

    private var titleText: String {
        displayTitle ?? session.displayTitle()
    }

    var body: some View {
        Group {
            switch style {
            case .regular:
                regularContent
            case .compact:
                compactContent
            }
        }
        .padding(.horizontal, style == .compact ? 10 : 14)
        .padding(.vertical, style == .compact ? 8 : 12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: style == .compact ? 14 : 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style == .compact ? 14 : 18, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: isSelected ? 1.4 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .animation(opencodeSelectionAnimation, value: isBusy)
        .animation(opencodeSelectionAnimation, value: hasLiveActivity)
        .animation(opencodeSelectionAnimation, value: hasDraft)
        .animation(opencodeSelectionAnimation, value: hasPermissionRequest)
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            SessionAvatar(title: titleText)

            VStack(alignment: .leading, spacing: 3) {
                if let workspaceOverline, !workspaceOverline.isEmpty {
                    Text(workspaceOverline)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    titleLine

                    Spacer(minLength: 8)

                    if let date = preview?.date {
                        SessionRelativeTimeText(date: date)
                    }
                }

                Text(preview?.text ?? String(localized: "No messages yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            SessionAvatar(title: titleText, size: 30)

            ShimmeringSessionTitle(text: titleText, active: shimmersTitle, font: .subheadline.weight(.medium), lineLimit: 1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if showsPinnedBadge {
                    compactIndicator(systemName: "pin.fill", color: .secondary)
                }
                if isBusy {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 7, height: 7)
                }
                if hasLiveActivity {
                    compactIndicator(systemName: "waveform", color: .indigo)
                }
                if hasDraft {
                    compactIndicator(systemName: "pencil", color: .secondary)
                }
                if hasPermissionRequest {
                    compactIndicator(systemName: "hand.raised.fill", color: .orange)
                }
            }
        }
    }

    private func compactIndicator(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private var titleLine: some View {
        Group {
            ShimmeringSessionTitle(text: titleText, active: shimmersTitle, font: .body.weight(.medium), lineLimit: 1)

            if isBusy {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }

            if hasLiveActivity {
                badgeIcon(systemName: "waveform", foreground: .indigo, background: Color.indigo.opacity(0.12))
            }

            if hasDraft {
                badgeIcon(systemName: "pencil", foreground: .secondary, background: Color.gray.opacity(0.12))
            }

            if hasPermissionRequest {
                badgeIcon(systemName: "hand.raised.fill", foreground: .orange, background: Color.orange.opacity(0.12))
            }
        }
    }

    private func badgeIcon(systemName: String, foreground: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }

    private var rowBackground: Color {
        isSelected ? Color.blue.opacity(0.10) : OpenCodePlatformColor.secondaryGroupedBackground
    }

    private var rowBorder: Color {
        isSelected ? Color.blue.opacity(0.28) : Color.primary.opacity(0.06)
    }
}

private struct ShimmeringSessionTitle: View {
    @Environment(\.scenePhase) private var scenePhase

    let text: String
    let active: Bool
    let font: Font
    let lineLimit: Int
    var alignment: TextAlignment = .leading

    @State private var phase: CGFloat = -1

    private var isAnimating: Bool {
        active && scenePhase == .active
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(isAnimating ? Color.primary.opacity(0.72) : Color.primary)
            .lineLimit(lineLimit)
            .multilineTextAlignment(alignment)
            .overlay {
                if isAnimating {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.85), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: max(geometry.size.width * 0.8, 36))
                        .offset(x: geometry.size.width * phase)
                        .blendMode(.plusLighter)
                    }
                    .mask(
                        Text(text)
                            .font(font)
                            .lineLimit(lineLimit)
                            .multilineTextAlignment(alignment)
                    )
                    .allowsHitTesting(false)
                }
            }
            .onAppear { updateAnimation(active: isAnimating) }
            .onChange(of: active) { _, _ in updateAnimation(active: isAnimating) }
            .onChange(of: scenePhase) { _, _ in updateAnimation(active: isAnimating) }
    }

    private func updateAnimation(active: Bool) {
        guard active else {
            phase = -1
            return
        }
        phase = -1
        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
            phase = 1.35
        }
    }
}
