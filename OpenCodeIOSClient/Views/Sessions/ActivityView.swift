import SwiftUI
import UIKit

struct ActivityView: View {
    @ObservedObject var facade: ActivityFacade
    let connection: ConnectionFacade
    let onSessionChosen: () -> Void
    @State private var excludedProjectIDs: Set<String> = []
    @State private var isShowingSettings = false

    var body: some View {
        ActivityContent(
            facade: facade,
            snapshot: facade.snapshot,
            excludedProjectIDs: excludedProjectIDs,
            showsLastUserMessage: facade.snapshot.showsLastUserMessage,
            onSessionChosen: onSessionChosen
        )
        .equatable()
        .safeAreaInset(edge: .bottom) {
            if !facade.snapshot.isReadOnly {
                HStack {
                    Spacer()
                    OpenCodeNewChatFloatingButton(
                        accessibilityIdentifier: "activity.newChat",
                        action: facade.presentNewChat
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, newChatBottomPadding)
            }
        }
        .navigationTitle("Activity")
        .opencodeInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Activity Settings")
                .accessibilityIdentifier("activity.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                projectFilterMenu
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ActivitySettingsSheet(facade: facade, connection: connection)
                .presentationDetents([.medium])
        }
        .task {
            await facade.prepareForPresentation()
        }
    }

    private var newChatBottomPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        16
        #else
        0
        #endif
    }

    private var projectFilterMenu: some View {
        Menu {
            Button {
                if allProjectsSelected {
                    excludedProjectIDs = Set(facade.snapshot.projects.map(\.id))
                } else {
                    excludedProjectIDs.removeAll()
                }
            } label: {
                Label(
                    "All Projects",
                    systemImage: allProjectsSelected ? "checkmark.circle.fill" : "circle"
                )
            }

            Divider()

            ForEach(facade.snapshot.projects) { project in
                Toggle(isOn: projectSelectionBinding(project.id)) {
                    Label {
                        Text(project.title)
                    } icon: {
                        Image(uiImage: ActivityProjectMenuAvatarRenderer.image(for: project))
                            .renderingMode(.original)
                    }
                }
            }
        } label: {
            Image(systemName: allProjectsSelected ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .disabled(facade.snapshot.projects.isEmpty)
        .accessibilityLabel("Filter Projects")
        .accessibilityIdentifier("activity.projectFilter")
    }

    private var allProjectsSelected: Bool {
        facade.snapshot.projects.allSatisfy { !excludedProjectIDs.contains($0.id) }
    }

    private func projectSelectionBinding(_ projectID: String) -> Binding<Bool> {
        Binding(
            get: { !excludedProjectIDs.contains(projectID) },
            set: { isSelected in
                if isSelected {
                    excludedProjectIDs.remove(projectID)
                } else {
                    excludedProjectIDs.insert(projectID)
                }
            }
        )
    }
}

private struct ActivitySettingsSheet: View {
    @ObservedObject var facade: ActivityFacade
    let connection: ConnectionFacade
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        RootConfigurationsView(facade: connection)
                    } label: {
                        Label("Global Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("activity.settings.global-settings")
                }

                Section {
                    Toggle(
                        "Show Last User Message",
                        isOn: Binding(
                            get: { facade.showsLastUserMessage },
                            set: { facade.setShowsLastUserMessage($0) }
                        )
                    )
                    .accessibilityIdentifier("activity.settings.showLastUserMessage")
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Turn this off to show only the latest assistant activity and fit more sessions on screen.")
                }
            }
            .navigationTitle("Activity Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

@MainActor
private enum ActivityProjectMenuAvatarRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(for project: ActivityFacade.ProjectFilterSnapshot) -> UIImage {
        let key = [
            project.id,
            project.title,
            project.icon?.override ?? "",
            project.icon?.url ?? "",
            project.icon?.color ?? "",
            project.usesGlobalAvatar.description,
        ].joined(separator: "|")
        if let image = cache[key] { return image }

        let renderer = ImageRenderer(
            content: ProjectAvatar(
                title: project.title,
                systemImage: project.usesGlobalAvatar ? "globe" : "folder.fill",
                icon: project.icon,
                usesSystemImageFallback: project.usesGlobalAvatar,
                isSelected: false,
                size: 24
            )
            .frame(width: 24, height: 24)
        )
        renderer.scale = UIScreen.main.scale
        let image = renderer.uiImage ?? UIImage(systemName: project.usesGlobalAvatar ? "globe" : "folder.fill")!
        cache[key] = image
        return image
    }
}

private struct ActivityContent: View, Equatable {
    let facade: ActivityFacade
    let snapshot: ActivityFacade.Snapshot
    let excludedProjectIDs: Set<String>
    let showsLastUserMessage: Bool
    let onSessionChosen: () -> Void

    nonisolated static func == (lhs: ActivityContent, rhs: ActivityContent) -> Bool {
        lhs.facade === rhs.facade
            && lhs.snapshot == rhs.snapshot
            && lhs.excludedProjectIDs == rhs.excludedProjectIDs
            && lhs.showsLastUserMessage == rhs.showsLastUserMessage
    }

    var body: some View {
        ZStack {
            OpenCodePlatformColor.groupedBackground
                .ignoresSafeArea()

            if snapshot.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading Activity")
                    .accessibilityIdentifier("activity.loading")
            } else {
                activityList
            }
        }
    }

    private var activityList: some View {
        List {
            if snapshot.isEmpty {
                ContentUnavailableView(
                    "No Recent Activity",
                    systemImage: "waveform.path.ecg",
                    description: Text("Sessions will appear here as you work across projects.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if visibleRowsAreEmpty {
                Group {
                    if allProjectsExcluded {
                        ContentUnavailableView(
                            "No Projects Selected",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Select at least one project from the filter menu.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No Matching Activity",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("No recent sessions belong to the selected projects.")
                        )
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if !needsInputRows.isEmpty {
                    activitySection(title: "Needs Input", systemImage: "hand.raised.fill", rows: needsInputRows)
                }

                if !workingRows.isEmpty {
                    activitySection(title: "Working", systemImage: "bolt.fill", rows: workingRows)
                }

                ForEach(recentSections) { section in
                    activitySection(
                        title: section.bucket.title,
                        systemImage: section.bucket.systemImage,
                        rows: section.rows
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(OpenCodePlatformColor.groupedBackground)
        .refreshable {
            await facade.prepareForPresentation(force: true)
        }
        .accessibilityIdentifier("activity.list")
        .animation(
            .snappy(duration: 0.42, extraBounce: 0.06),
            value: snapshot.placementSignature + "|filters:" + excludedProjectIDs.sorted().joined(separator: ",")
        )
    }

    private var needsInputRows: [ActivityFacade.RowSnapshot] {
        visible(snapshot.needsInputRows)
    }

    private var workingRows: [ActivityFacade.RowSnapshot] {
        visible(snapshot.workingRows)
    }

    private var recentRows: [ActivityFacade.RowSnapshot] {
        visible(snapshot.recentRows)
    }

    private var recentSections: [ActivityRecentSection] {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        return ActivityRecentBucket.allCases.compactMap { bucket in
            let rows = recentRows.filter {
                ActivityRecentBucket.bucket(for: $0.updatedAt, now: now, calendar: calendar) == bucket
            }
            return rows.isEmpty ? nil : ActivityRecentSection(bucket: bucket, rows: rows)
        }
    }

    private var visibleRowsAreEmpty: Bool {
        needsInputRows.isEmpty && workingRows.isEmpty && recentRows.isEmpty
    }

    private var allProjectsExcluded: Bool {
        !snapshot.projects.isEmpty && snapshot.projects.allSatisfy { excludedProjectIDs.contains($0.id) }
    }

    private func visible(_ rows: [ActivityFacade.RowSnapshot]) -> [ActivityFacade.RowSnapshot] {
        rows.filter { !excludedProjectIDs.contains($0.projectID) }
    }

    private func activitySection(
        title: LocalizedStringKey,
        systemImage: String,
        rows: [ActivityFacade.RowSnapshot]
    ) -> some View {
        Section {
            ForEach(rows) { row in
                Button {
                    facade.prepareSelection(row)
                    withAnimation(opencodeSelectionAnimation) {
                        onSessionChosen()
                    }
                    Task { await facade.open(row) }
                } label: {
                    ActivitySessionRow(
                        row: row,
                        showsLastUserMessage: showsLastUserMessage,
                        isSelected: snapshot.selectedSessionID == row.recent.session.id
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("activity.session.\(row.recent.session.id)")
                .task(id: row.hydrationGeneration) {
                    await facade.hydrateIfNeeded(row)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !snapshot.isReadOnly {
                        Button(role: .destructive) {
                            Task { await facade.delete(row) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

#if !targetEnvironment(macCatalyst)
                        Button {
                            Task { await facade.toggleLiveActivity(row) }
                        } label: {
                            Label(
                                row.isLiveActivityActive ? LocalizedStringResource("Stop Live") : LocalizedStringResource("Live"),
                                systemImage: row.isLiveActivityActive ? "waveform.slash" : "waveform"
                            )
                        }
                        .tint(.indigo)
#endif
                    }
                }
            }
        } header: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .textCase(nil)
        }
    }
}

enum ActivityRecentBucket: Int, CaseIterable, Identifiable {
    case recent
    case yesterday
    case lastWeek
    case older

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .recent: "Recent"
        case .yesterday: "Yesterday"
        case .lastWeek: "Last Week"
        case .older: "Older"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .yesterday: "sun.horizon"
        case .lastWeek: "calendar"
        case .older: "archivebox"
        }
    }

    static func bucket(for date: Date?, now: Date, calendar: Calendar) -> ActivityRecentBucket {
        guard let date else { return .older }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfYesterday
        if date >= startOfToday { return .recent }
        if date >= startOfYesterday { return .yesterday }
        if date >= startOfLastWeek { return .lastWeek }
        return .older
    }
}

private struct ActivityRecentSection: Identifiable {
    let bucket: ActivityRecentBucket
    let rows: [ActivityFacade.RowSnapshot]

    var id: ActivityRecentBucket.ID { bucket.id }
}

struct ActivitySessionRow: View {
    let row: ActivityFacade.RowSnapshot
    let showsLastUserMessage: Bool
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ActivityAvatarStack(
                    sessionTitle: title,
                    projectTitle: row.recent.projectTitle,
                    projectIcon: row.projectIcon,
                    usesGlobalProjectAvatar: row.usesGlobalProjectAvatar
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(row.recent.projectTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    ActivityStatusPill(
                        title: row.isHydrating && !row.needsInput ? Text("Updating") : Text(row.statusTitle),
                        isWorking: row.isWorking,
                        isHydrating: row.isHydrating,
                        needsInput: row.needsInput
                    )
                    if let updatedAt = row.updatedAt {
                        SessionRelativeTimeText(date: updatedAt)
                    }
                }
            }

            if showsLastUserMessage, let userText = row.latestUserText {
                ActivityTranscriptLine(label: "You", text: userText, tint: .secondary)
                    .accessibilityIdentifier("activity.session.\(row.recent.session.id).latest-user")
            }

            if let tool = row.runningTools.first {
                ActivityInlineToolLine(
                    label: latestLabel,
                    tool: tool
                )
            } else if let assistantText = row.latestAssistantText {
                ActivityTranscriptLine(
                    label: latestLabel,
                    text: assistantText,
                    tint: row.isWorking ? .primary : .secondary
                )
            } else {
                Text("Open the session to see the conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if row.pendingInteractionCount > 0 || row.todoCount > 0 || row.isLiveActivityActive {
                HStack(spacing: 12) {
                    if row.pendingInteractionCount > 0 {
                        Label("\(row.pendingInteractionCount) waiting", systemImage: "hand.raised.fill")
                            .foregroundStyle(.orange)
                    }
                    if row.todoCount > 0 {
                        Label("\(row.completedTodoCount)/\(row.todoCount)", systemImage: "checklist")
                            .foregroundStyle(.secondary)
                    }
                    if row.isLiveActivityActive {
                        Label("Live", systemImage: "waveform")
                            .foregroundStyle(.indigo)
                            .accessibilityIdentifier("activity.session.\(row.recent.session.id).liveActivity")
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardBackground: Color {
        if row.needsInput { return Color.orange.opacity(0.1) }
        if row.isWorking { return Color.accentColor.opacity(0.09) }
        return OpenCodePlatformColor.secondaryGroupedBackground
    }

    private var cardBorder: Color {
        if isSelected { return Color.accentColor.opacity(0.82) }
        if row.needsInput { return Color.orange.opacity(0.24) }
        if row.isWorking { return Color.accentColor.opacity(0.2) }
        return Color.primary.opacity(0.06)
    }

    private var title: String {
        guard let title = row.recent.session.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return String(localized: "Untitled Session")
        }
        return title
    }

    private var latestLabel: LocalizedStringKey? {
        guard showsLastUserMessage else { return nil }
        return row.isWorking ? "Now" : "Latest"
    }

}

struct SessionRelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(Self.label(for: date, at: context.date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    static func label(for date: Date, at now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        let isFuture = interval < 0
        let seconds = abs(interval)
        guard seconds >= 60 else { return String(localized: "Now") }

        let value: Int
        let unit: String
        if seconds < 3_600 {
            value = max(1, Int(seconds / 60))
            unit = String(localized: "m", comment: "Abbreviated unit for minutes in a compact relative timestamp.")
        } else if seconds < 86_400 {
            value = max(1, Int(seconds / 3_600))
            unit = String(localized: "h", comment: "Abbreviated unit for hours in a compact relative timestamp.")
        } else {
            value = max(1, Int(seconds / 86_400))
            unit = String(localized: "d", comment: "Abbreviated unit for days in a compact relative timestamp.")
        }
        if isFuture {
            return String(localized: "in \(value)\(unit)", comment: "Compact relative time in the future. The first value is a number and the second is the localized abbreviated unit (m, h, or d).")
        }
        return String(localized: "\(value)\(unit) ago", comment: "Compact relative time in the past. The first value is a number and the second is the localized abbreviated unit (m, h, or d).")
    }
}

private struct ActivityAvatarStack: View {
    let sessionTitle: String
    let projectTitle: String
    let projectIcon: OpenCodeProject.Icon?
    let usesGlobalProjectAvatar: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ProjectAvatar(
                title: projectTitle,
                systemImage: usesGlobalProjectAvatar ? "globe" : "folder.fill",
                icon: projectIcon,
                usesSystemImageFallback: usesGlobalProjectAvatar,
                isSelected: false,
                size: 36
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            SessionAvatar(title: sessionTitle, size: 27)
                .overlay {
                    Circle()
                        .stroke(OpenCodePlatformColor.secondaryGroupedBackground, lineWidth: 3)
                }
        }
        .frame(width: 48, height: 42)
        .accessibilityHidden(true)
    }
}

private struct ActivityInlineToolLine: View {
    let label: LocalizedStringKey?
    let tool: ActivityFacade.ToolSnapshot
    @ScaledMetric(relativeTo: .subheadline) private var previewLineHeight = 20.0

    private var appearance: OpenCodeToolActivityAppearance {
        OpenCodeToolActivityAppearance.resolve(tool.tool)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let label {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
            }

            HStack(spacing: 9) {
                Image(systemName: appearance.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appearance.tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let detail = tool.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                ProgressView()
                    .controlSize(.mini)
                    .tint(appearance.tint)
            }
            .frame(height: previewLineHeight * 2, alignment: .top)
        }
    }
}

private struct ActivityTranscriptLine: View {
    let label: LocalizedStringKey?
    let text: String
    let tint: Color
    @ScaledMetric(relativeTo: .subheadline) private var previewLineHeight = 20.0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let label {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
            }

            ActivityTailPreview(text: text, tint: tint)
            .frame(maxWidth: .infinity)
            .frame(height: previewLineHeight * 2)
        }
    }
}

struct ActivityTailPreview: View {
    let text: String
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            Text(Self.fittingText(
                text,
                width: geometry.size.width,
                font: .preferredFont(forTextStyle: .subheadline)
            ))
            .font(.subheadline)
            .foregroundStyle(tint)
            .lineLimit(2)
            .frame(width: geometry.size.width, alignment: .leading)
            .accessibilityLabel(text)
        }
    }

    static func fittingText(_ text: String, width: CGFloat, font: UIFont, maximumLines: Int = 2) -> String {
        guard width > 0, maximumLines > 0, !text.isEmpty else { return text }
        let maximumHeight = measuredHeight(
            of: Array(repeating: "Ag", count: maximumLines).joined(separator: "\n"),
            width: width,
            font: font
        )
        if measuredHeight(of: text, width: width, font: font) <= maximumHeight {
            return text
        }

        let characters = Array(text)
        var lowerBound = 0
        var upperBound = characters.count
        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            let candidate = "…" + String(characters[midpoint...])
            if measuredHeight(of: candidate, width: width, font: font) <= maximumHeight {
                upperBound = midpoint
            } else {
                lowerBound = midpoint + 1
            }
        }

        let suffix = String(characters[lowerBound...]).drop(while: {
            $0.isWhitespace || $0 == "." || $0 == "·"
        })
        return "…" + suffix
    }

    private static func measuredHeight(of text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        return (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraphStyle],
            context: nil
        ).height
    }

}

private struct ActivityStatusPill: View {
    let title: Text
    let isWorking: Bool
    let isHydrating: Bool
    let needsInput: Bool

    var body: some View {
        HStack(spacing: 5) {
            if !needsInput && isHydrating {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 6, height: 6)
            }
            title
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(
            needsInput
                ? Color.orange
                : (isWorking && !isHydrating ? Color.accentColor : Color.secondary)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            (needsInput ? Color.orange : (isWorking && !isHydrating ? Color.accentColor : Color.secondary)).opacity(0.1),
            in: Capsule()
        )
    }
}
