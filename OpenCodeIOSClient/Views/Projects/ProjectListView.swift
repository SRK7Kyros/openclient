import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ProjectListView: View {
    @ObservedObject var viewModel: AppViewModel
    let onProjectChosen: () -> Void
    @State private var projectForColorPicker: OpenCodeProject?
    @State private var projectForImagePicker: OpenCodeProject?

    var body: some View {
        let projectIDs = viewModel.projects.map { $0.id }.joined(separator: "|")
        let recentSessions = viewModel.recentProjectSessions
        let isLoadingRecentSessions = viewModel.isLoadingRecentProjectSessions

        List {
            Section {
                ForEach(viewModel.projects) { project in
                    let title = projectTitle(project)
                    ProjectRow(
                        title: title,
                        subtitle: project.id == "global" ? "Shared sessions across the current server context" : project.worktree,
                        systemImage: project.id == "global" ? "globe" : "folder.fill",
                        icon: project.icon,
                        isSelected: viewModel.isProjectSelected(project)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.currentProject = project
                        viewModel.prepareDirectorySelection(project.id == "global" ? nil : project.worktree)
                        withAnimation(opencodeSelectionAnimation) {
                            onProjectChosen()
                        }
                        Task {
                            await viewModel.selectProject(project)
                        }
                    }
                    .contextMenu {
                        if viewModel.canEditProjectPreferences(project) {
                            Button {
                                projectForColorPicker = project
                            } label: {
                                Label("Set Color", systemImage: "paintpalette")
                            }

                            Button {
                                projectForImagePicker = project
                            } label: {
                                Label("Set Image", systemImage: "photo.on.rectangle")
                            }

                            if project.icon?.override?.isEmpty == false {
                                Button(role: .destructive) {
                                    Task { await viewModel.setProjectImageOverride(nil, for: project) }
                                } label: {
                                    Label("Clear Image", systemImage: "trash")
                                }
                            }
                        } else {
                            Label("Preferences unavailable", systemImage: "lock")
                        }
                    }
                }
            } header: {
                ProjectListSectionHeader(recentSessions: recentSessions, isLoadingRecentSessions: isLoadingRecentSessions) { recent in
                    viewModel.prepareRecentProjectSessionSelection(recent)
                    withAnimation(opencodeSelectionAnimation) {
                        onProjectChosen()
                    }
                    Task {
                        await viewModel.openRecentProjectSession(recent)
                    }
                }
                .textCase(nil)
            }

            if viewModel.funAndGamesPreferences.showsSection {
                Section {
                    ProjectRow(
                        title: "Find the Place",
                        subtitle: "Guess a secret city from live weather clues",
                        systemImage: "map.fill",
                        usesSystemImageFallback: true,
                        isSelected: false
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.presentFindPlaceModelSheet()
                    }

                    ProjectRow(
                        title: "Find the Bug",
                        subtitle: "Spot the hidden bug in a generated code snippet",
                        systemImage: "ladybug.fill",
                        usesSystemImageFallback: true,
                        isSelected: false
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.presentFindBugLanguageSheet()
                    }
                } header: {
                    Text("Fun & Games")
                        .font(ProjectListLayout.roundedSectionTitleFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

        }
        .listStyle(.sidebar)
        .scrollClipDisabled()
        .refreshable {
            await viewModel.refreshProjectList()
        }
        .task(id: projectIDs) {
            await viewModel.loadRecentProjectSessionsAcrossProjects()
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .opencodeLeading) {
                Button {
                    viewModel.disconnect()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Disconnect")
                .accessibilityIdentifier("projects.disconnect")
            }

            ToolbarItem(placement: .opencodeTrailing) {
                Button {
                    viewModel.presentConfigurationsSheet()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Configurations")
                .accessibilityIdentifier("projects.configurations")
            }

            ToolbarItem(placement: .opencodeTrailing) {
                Button {
                    viewModel.presentCreateProjectSheet()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Project")
                .accessibilityIdentifier("projects.create")
            }
        }
        .sheet(isPresented: $viewModel.isShowingCreateProjectSheet) {
            CreateProjectSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingConfigurationsSheet) {
            ConfigurationsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingFindPlaceModelSheet) {
            FindPlaceModelSelectionSheet(viewModel: viewModel, onGameStarted: onProjectChosen)
        }
        .sheet(isPresented: $viewModel.isShowingFindBugLanguageSheet) {
            FindBugLanguageSelectionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingFindBugModelSheet) {
            FindBugModelSelectionSheet(viewModel: viewModel, onGameStarted: onProjectChosen)
        }
        .sheet(item: $projectForColorPicker) { project in
            ProjectColorPickerSheet(viewModel: viewModel, project: project)
        }
        .sheet(item: $projectForImagePicker) { project in
            ProjectImagePickerSheet(viewModel: viewModel, project: project)
        }
        .animation(opencodeSelectionAnimation, value: viewModel.selectedDirectory)
        .animation(opencodeSelectionAnimation, value: projectIDs)
    }

    private func projectTitle(_ project: OpenCodeProject) -> String {
        if project.id == "global" {
            return "Global"
        }
        return project.name ?? project.worktree.split(separator: "/").last.map(String.init) ?? project.worktree
    }
}

private struct ProjectListSectionHeader: View {
    let recentSessions: [RecentProjectSession]
    let isLoadingRecentSessions: Bool
    let onSelectRecentSession: (RecentProjectSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingRecentSessions || !recentSessions.isEmpty {
                RecentProjectSessionSection(
                    sessions: recentSessions,
                    isLoading: isLoadingRecentSessions,
                    onSelect: onSelectRecentSession
                )
            }

            Text("Projects")
                .font(ProjectListLayout.sectionTitleFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, ProjectListLayout.contentMargin)
        }
        .padding(.top, isLoadingRecentSessions || !recentSessions.isEmpty ? 8 : 0)
        .scrollClipDisabled()
    }
}

private struct RecentProjectSessionSection: View {
    let sessions: [RecentProjectSession]
    let isLoading: Bool
    let onSelect: (RecentProjectSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(ProjectListLayout.sectionTitleFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, ProjectListLayout.contentMargin)

            RecentProjectSessionRail(sessions: sessions, isLoading: isLoading, onSelect: onSelect)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .scrollClipDisabled()
    }
}

private struct RecentProjectSessionRail: View {
    let sessions: [RecentProjectSession]
    let isLoading: Bool
    let onSelect: (RecentProjectSession) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if sessions.isEmpty && isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RecentProjectSessionSkeletonCard()
                    }
                } else {
                    ForEach(sessions) { recent in
                        Button {
                            onSelect(recent)
                        } label: {
                            RecentProjectSessionCard(recent: recent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .offset(x: -ProjectListLayout.railContentOffset)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("projects.recentSessions")
    }
}

private struct RecentProjectSessionSkeletonCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 94, height: 10)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 66, height: 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 176, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(OpenCodePlatformColor.secondaryGroupedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading recent session")
    }
}

private struct RecentProjectSessionCard: View {
    let recent: RecentProjectSession

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SessionAvatar(title: title)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(recent.projectTitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if recent.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 176, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(OpenCodePlatformColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel("Open recent session \(title) in \(recent.projectTitle)")
    }

    private var title: String {
        recent.session.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? recent.session.title ?? "Session"
            : "Session"
    }
}

private enum ProjectListLayout {
    static let contentMargin: CGFloat = 16
    static let railContentOffset: CGFloat = 22
    static let sectionTitleFont = Font.system(.footnote, design: .default).weight(.semibold)
    static let roundedSectionTitleFont = Font.system(.footnote, design: .rounded).weight(.semibold)
}

private struct ProjectColorPickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let project: OpenCodeProject
    @Environment(\.dismiss) private var dismiss

    private let colors = ["pink", "mint", "orange", "purple", "cyan", "lime"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                ProjectRow(
                    title: project.name ?? URL(fileURLWithPath: project.worktree).lastPathComponent,
                    subtitle: project.worktree,
                    systemImage: "folder.fill",
                    icon: project.icon,
                    isSelected: false
                )
                .padding(.horizontal)
                .padding(.top, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(colors, id: \.self) { color in
                        Button {
                            Task {
                                await viewModel.setProjectColor(color, for: project)
                                dismiss()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ProjectColorSwatch(color: color, title: project.name ?? project.worktree)
                                Text(color.capitalized)
                                    .font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(project.icon?.color == color ? Color.accentColor : Color.clear, lineWidth: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .navigationTitle("Project Color")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ProjectImagePickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let project: OpenCodeProject
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [ProjectImageCandidate] = []
    @State private var thumbnails: [String: String] = [:]
    @State private var isLoading = true
    @State private var selectedPath: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Searching images...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Images Found",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("OpenClient searched for PNG, JPG, and JPEG files in this project.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(candidates) { candidate in
                                Button {
                                    Task { await select(candidate) }
                                } label: {
                                    ProjectImageCandidateCell(
                                        candidate: candidate,
                                        dataURL: thumbnails[candidate.path],
                                        isSelected: selectedPath == candidate.path
                                    )
                                }
                                .buttonStyle(.plain)
                                .task {
                                    await loadThumbnailIfNeeded(candidate)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Project Image")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .opencodeTrailing) {
                    if project.icon?.override?.isEmpty == false {
                        Button("Clear", role: .destructive) {
                            Task {
                                await viewModel.setProjectImageOverride(nil, for: project)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .task {
                candidates = await viewModel.discoverProjectImageCandidates(for: project)
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadThumbnailIfNeeded(_ candidate: ProjectImageCandidate) async {
        guard thumbnails[candidate.path] == nil else { return }
        guard let dataURL = await viewModel.projectImageDataURL(for: candidate, project: project) else { return }
        thumbnails[candidate.path] = dataURL
    }

    private func select(_ candidate: ProjectImageCandidate) async {
        selectedPath = candidate.path
        if thumbnails[candidate.path] == nil {
            await loadThumbnailIfNeeded(candidate)
        }
        guard let dataURL = thumbnails[candidate.path] else {
            selectedPath = nil
            return
        }
        await viewModel.setProjectImageOverride(dataURL, for: project)
        dismiss()
    }
}

private struct ProjectColorSwatch: View {
    let color: String
    let title: String

    var body: some View {
        let colors = swatchColors(for: color)
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colors.background)
            Text(title.first.map { String($0).uppercased() } ?? "?")
                .font(.title3.weight(.bold))
                .foregroundStyle(colors.foreground)
        }
        .frame(width: 58, height: 58)
    }

    private func swatchColors(for value: String) -> (background: Color, foreground: Color) {
        switch value {
        case "pink": return (Color(red: 0.96, green: 0.45, blue: 0.70), .white)
        case "mint": return (Color(red: 0.25, green: 0.82, blue: 0.62), Color.black.opacity(0.78))
        case "orange": return (Color(red: 0.98, green: 0.57, blue: 0.24), .white)
        case "purple": return (Color(red: 0.58, green: 0.45, blue: 0.86), .white)
        case "cyan": return (Color(red: 0.13, green: 0.79, blue: 0.89), Color.black.opacity(0.78))
        default: return (Color(red: 0.62, green: 0.82, blue: 0.20), Color.black.opacity(0.78))
        }
    }
}

private struct ProjectImageCandidateCell: View {
    let candidate: ProjectImageCandidate
    let dataURL: String?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                if let dataURL, let image = projectPreferencePlatformImage(from: dataURL) {
                    projectPreferencePlatformImageView(image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }

            Text(candidate.filename)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(candidate.displayPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#if canImport(UIKit)
private func projectPreferencePlatformImage(from dataURL: String) -> UIImage? {
    guard let comma = dataURL.firstIndex(of: ","), dataURL[..<comma].contains("base64") else { return nil }
    guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
    return UIImage(data: data)
}

private func projectPreferencePlatformImageView(_ image: UIImage) -> Image {
    Image(uiImage: image)
}
#elseif canImport(AppKit)
private func projectPreferencePlatformImage(from dataURL: String) -> NSImage? {
    guard let comma = dataURL.firstIndex(of: ","), dataURL[..<comma].contains("base64") else { return nil }
    guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else { return nil }
    return NSImage(data: data)
}

private func projectPreferencePlatformImageView(_ image: NSImage) -> Image {
    Image(nsImage: image)
}
#endif

private struct FindBugLanguageSelectionSheet: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the language for the buggy snippet. These match the app's syntax highlighting support.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Languages") {
                    ForEach(FindBugGame.supportedLanguages) { language in
                        Button {
                            viewModel.selectFindBugLanguage(language)
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .foregroundStyle(.tint)
                                Text(language.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Find the Bug")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") {
                        viewModel.isShowingFindBugLanguageSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FindBugModelSelectionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onGameStarted: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the model that will generate the buggy code and judge your answer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.sortedProviders) { provider in
                    Section(provider.name) {
                        ForEach(provider.models.values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.id) { model in
                            let reference = OpenCodeModelReference(providerID: provider.id, modelID: model.id)
                            Button {
                                Task {
                                    await viewModel.startFindBugGame(model: reference)
                                    onGameStarted()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.tint)
                                    Text(model.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.pendingFindBugLanguage?.title ?? "Model")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Back") {
                        viewModel.isShowingFindBugModelSheet = false
                        viewModel.isShowingFindBugLanguageSheet = true
                    }
                }
                ToolbarItem(placement: .opencodeTrailing) {
                    Button("Cancel") {
                        viewModel.isShowingFindBugModelSheet = false
                        viewModel.pendingFindBugLanguage = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FindPlaceModelSelectionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onGameStarted: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the model that will host the game. OpenClient will start a new chat and send the private game setup automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.sortedProviders) { provider in
                    Section(provider.name) {
                        ForEach(provider.models.values.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.id) { model in
                            let reference = OpenCodeModelReference(providerID: provider.id, modelID: model.id)
                            Button {
                                Task {
                                    await viewModel.startFindPlaceGame(model: reference)
                                    onGameStarted()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.tint)
                                    Text(model.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
            }
            .navigationTitle("Find the Place")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") {
                        viewModel.isShowingFindPlaceModelSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
