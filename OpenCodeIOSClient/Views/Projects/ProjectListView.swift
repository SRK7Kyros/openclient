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
        let recentLoadKey = [
            viewModel.config.recentServerID,
            viewModel.isConnected ? "connected" : "disconnected",
            viewModel.showsRecentSessionsInProjectList ? "recent-on" : "recent-off",
            projectIDs,
        ].joined(separator: "|")
        let recentSessions = viewModel.recentProjectSessions
        let isLoadingRecentSessions = viewModel.isLoadingRecentProjectSessions
        let isShowingProjectSessionSearch = !viewModel.projectSessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        List {
            if isShowingProjectSessionSearch {
                ProjectSessionSearchSection(
                    query: viewModel.projectSessionSearchQuery,
                    results: viewModel.projectSessionSearchResults,
                    isLoading: viewModel.isSearchingProjectSessions,
                    onSelect: openProjectSession
                )
            } else {
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
                        openProjectSession(recent)
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

        }
        .listStyle(.sidebar)
        .scrollClipDisabled()
        .refreshable {
            guard !isScreenshotScene else { return }
            await viewModel.refreshProjectList()
        }
        .safeAreaInset(edge: .bottom) {
            ProjectListBottomBar(
                query: Binding(
                    get: { viewModel.projectSessionSearchQuery },
                    set: { viewModel.projectSessionSearchQuery = $0 }
                ),
                isSearching: viewModel.isSearchingProjectSessions,
                onNewChat: {
                    viewModel.presentNewProjectChatSheet()
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task(id: recentLoadKey) {
            guard !isScreenshotScene else { return }
            await viewModel.loadRecentProjectSessionsAcrossProjects()
        }
        .task(id: viewModel.projectSessionSearchQuery) {
            guard !isScreenshotScene else { return }
            let query = viewModel.projectSessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await viewModel.searchProjectSessionsAcrossProjects()
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

    private var isScreenshotScene: Bool {
        ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] != nil
    }

    private func openProjectSession(_ recent: RecentProjectSession) {
        viewModel.prepareRecentProjectSessionSelection(recent)
        withAnimation(opencodeSelectionAnimation) {
            onProjectChosen()
        }
        Task {
            await viewModel.openRecentProjectSession(recent)
        }
    }
}

private struct ProjectSessionSearchSection: View {
    let query: String
    let results: [RecentProjectSession]
    let isLoading: Bool
    let onSelect: (RecentProjectSession) -> Void

    var body: some View {
        Section {
            if results.isEmpty && isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching chats...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if results.isEmpty {
                Text("No chats match \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(results) { recent in
                    Button {
                        onSelect(recent)
                    } label: {
                        ProjectSessionSearchRow(recent: recent)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Chats")
                .font(ProjectListLayout.sectionTitleFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
}

private struct ProjectSessionSearchRow: View {
    let recent: RecentProjectSession

    var body: some View {
        HStack(spacing: 12) {
            SessionAvatar(title: title)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if recent.isBusy {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(recent.preview?.text ?? recent.projectTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(recent.projectTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var title: String {
        let trimmed = recent.session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed ?? "Session" : "Session"
    }
}

private struct ProjectListBottomBar: View {
    @Binding var query: String
    let isSearching: Bool
    let onNewChat: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                TextField("Search Chats", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit {
                        isSearchFocused = false
                    }
                    .accessibilityIdentifier("projects.searchChats")

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel("Clear chat search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: ProjectListLayout.bottomBarHeight)
            .opencodeConcentricGlassSurface(minimumCornerRadius: ProjectListLayout.bottomBarHeight / 2, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 16, y: 5)

            if isSearchFocused {
                Button {
                    dismissSearchFocus()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: ProjectListLayout.bottomBarHeight, height: ProjectListLayout.bottomBarHeight)
                        .contentShape(Circle())
                        .opencodeConcentricGlassSurface(minimumCornerRadius: ProjectListLayout.bottomBarHeight / 2, in: Circle())
                }
                .buttonStyle(.plain)
                .frame(width: ProjectListLayout.bottomBarHeight, height: ProjectListLayout.bottomBarHeight)
                .contentShape(Circle())
                .accessibilityLabel("Dismiss Search")
                .accessibilityIdentifier("projects.search.dismiss")
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .zIndex(1)
            } else {
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(newChatButtonForeground)
                        .frame(width: ProjectListLayout.bottomBarHeight - 14, height: ProjectListLayout.bottomBarHeight - 14)
                }
                .frame(height: ProjectListLayout.bottomBarHeight)
                .opencodePrimaryGlassButton()
                .buttonBorderShape(.capsule)
                .accessibilityLabel("New Chat")
                .accessibilityIdentifier("projects.newChat")
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, isSearchFocused ? 8 : 0)
        .animation(opencodeSelectionAnimation, value: isSearchFocused)
    }

    private func dismissSearchFocus() {
        isSearchFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    private var newChatButtonForeground: Color {
        #if os(iOS) || targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            return .white
        }
        #endif
        return .primary
    }
}

private struct InlineSubtitleSelectTrigger: View {
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .underline(true, color: .secondary.opacity(0.75))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .baselineOffset(1)
        }
        .contentShape(Rectangle())
    }
}

struct ProjectNewChatSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let request: NewProjectChatSheetRequest
    let autoFocusInput: Bool
    let onChatStarted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draftStore = MessageComposerDraftStore()
    @State private var attachments: [OpenCodeComposerAttachment] = []
    @State private var isComposerMenuOpen = false
    @State private var composerAccessoryExpansion: ComposerAccessoryExpansion = .collapsed
    @State private var selectedAttachmentPreview: OpenCodeComposerAttachment?
    @State private var isStartingChat = false
    @State private var selectedProjectID = ""
    @State private var workspaceSelection: NewSessionWorkspaceSelection = .main
    @State private var newWorkspaceName = ""
    @State private var hasInitializedSelection = false
    @State private var hasAppliedInitialWorkspace = false
    @State private var selectedAgentName: String?
    @State private var selectedModelReference: OpenCodeModelReference?
    @State private var selectedReasoningVariant: String?
    @State private var hasInitializedComposerSettings = false
    @State private var chatTitleDraft = ""
    @State private var isEditingChatTitle = false
    @State private var startingSnapshot: NewSessionStartingSnapshot?
    @FocusState private var isChatTitleFocused: Bool

    init(viewModel: AppViewModel, request: NewProjectChatSheetRequest, autoFocusInput: Bool = true, onChatStarted: @escaping () -> Void) {
        self.viewModel = viewModel
        self.request = request
        self.autoFocusInput = autoFocusInput
        self.onChatStarted = onChatStarted
        _selectedProjectID = State(initialValue: request.projectID ?? "")
        _selectedAgentName = State(initialValue: request.composerSelection?.agentName)
        _selectedModelReference = State(initialValue: request.composerSelection?.modelReference)
        _selectedReasoningVariant = State(initialValue: request.composerSelection?.reasoningVariant)
        _attachments = State(initialValue: request.initialContent?.attachments ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OpenCodePlatformColor.groupedBackground
                    .ignoresSafeArea()
                    .ignoresSafeArea(.keyboard, edges: .bottom)

                newChatBody
                    .padding(.horizontal, 24)
                    .padding(.bottom, startingSnapshot == nil ? 96 : 0)

                if startingSnapshot == nil {
                    VStack(spacing: 6) {
                        if !attachments.isEmpty {
                            ComposerAccessoryArea(
                                todos: [],
                                attachments: attachments,
                                expansion: $composerAccessoryExpansion,
                                onTapTodo: {},
                                onTapAttachment: { attachment in
                                    selectedAttachmentPreview = attachment
                                },
                                onRemoveAttachment: removeAttachment
                            )
                            .padding(.horizontal, 16)
                        }

                        NewChatInputBar(
                            draftStore: draftStore,
                            isAccessoryMenuOpen: $isComposerMenuOpen,
                            attachmentCount: attachments.count,
                            isSending: isStartingChat || viewModel.isLoading,
                            canSend: selectedProject != nil,
                            autoFocus: autoFocusInput && !isEditingChatTitle && !isChatTitleFocused,
                            usesKeyboardBottomPadding: isEditingChatTitle || isChatTitleFocused,
                            onSend: startChat,
                            onAddAttachments: addAttachments
                        )
                    }
                }
            }
            .sheet(item: $selectedAttachmentPreview) { attachment in
                NavigationStack {
                    AttachmentPreviewSheet(attachment: attachment)
                }
            }
            .background {
                OpenCodePlatformColor.groupedBackground
                    .ignoresSafeArea()
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationTitle(visibleChatTitle)
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") { dismissSheet() }
                        .disabled(startingSnapshot != nil)
                }

                ToolbarItem(placement: .principal) {
                    editableNavigationChatTitle
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let initialContent = request.initialContent,
               !initialContent.text.isEmpty,
               draftStore.text.isEmpty {
                draftStore.text = initialContent.text
            }
            initializeSelectionIfNeeded()
            initializeComposerSettingsIfNeeded()
        }
        .onChange(of: selectedProjectID) { _, _ in
            syncWorkspaceSelection()
        }
        .onChange(of: viewModel.projects.map(\.id).joined(separator: "|")) { _, _ in
            initializeSelectionIfNeeded()
        }
        .onChange(of: selectedModelReference) { _, _ in
            syncReasoningSelection()
        }
        .onChange(of: composerSettingsSourceSignature) { _, _ in
            initializeComposerSettingsIfNeeded()
        }
        .onChange(of: isChatTitleFocused) { _, isFocused in
            if !isFocused, isEditingChatTitle {
                finishEditingChatTitle()
            }
        }
    }

    @ViewBuilder
    private var newChatBody: some View {
        if let startingSnapshot {
            NewSessionStartingPreview(snapshot: startingSnapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.projects.isEmpty {
            ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Refresh projects before starting a new chat."))
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 14) {
                Spacer(minLength: 0)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.92))
                    .padding(.bottom, 4)

                editableChatTitle

                destinationSubtitle

                newWorktreeFields

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var editableChatTitle: some View {
        Text(visibleChatTitle)
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(chatTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .primary : Color.accentColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
            .onTapGesture(perform: beginEditingChatTitle)
            .accessibilityLabel("Rename chat")
            .accessibilityIdentifier("projects.newChat.titleButton")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var editableNavigationChatTitle: some View {
        if isEditingChatTitle {
            TextField("New Session", text: $chatTitleDraft)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($isChatTitleFocused)
                .onSubmit { finishEditingChatTitle() }
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
                .frame(width: 230)
                .accessibilityLabel("Chat title")
                .accessibilityIdentifier("projects.newChat.titleField")
        } else {
            Button(action: beginEditingChatTitle) {
                HStack(spacing: 5) {
                    Text(visibleChatTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 230)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename chat")
            .accessibilityIdentifier("projects.newChat.navigationTitleButton")
        }
    }

    private var visibleChatTitle: String {
        let trimmedTitle = chatTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "New Session" : trimmedTitle
    }

    private var submittedChatTitle: String {
        chatTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishEditingChatTitle() {
        isChatTitleFocused = false
        withAnimation(opencodeSelectionAnimation) {
            isEditingChatTitle = false
        }
    }

    private func beginEditingChatTitle() {
        isComposerMenuOpen = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
        withAnimation(opencodeSelectionAnimation) {
            isEditingChatTitle = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isChatTitleFocused = true
        }
    }

    @ViewBuilder
    private var destinationSubtitle: some View {
        VStack(spacing: 8) {
            destinationLine
            composerSettingsLine
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var destinationLine: some View {
        ViewThatFits(in: .horizontal) {
            destinationLineContent

            VStack(spacing: 9) {
                HStack(spacing: 7) {
                    Text("New session in")
                    projectSelectTrigger
                }
                if showsWorkspacePicker {
                    HStack(spacing: 7) {
                        Text("in")
                        workspaceSelectTrigger
                        Text("workspace")
                    }
                }
            }
        }
    }

    private var destinationLineContent: some View {
        HStack(spacing: 7) {
            Text("New session in")
            projectSelectTrigger
            if showsWorkspacePicker {
                Text("in")
                workspaceSelectTrigger
                Text("workspace")
            }
        }
    }

    @ViewBuilder
    private var composerSettingsLine: some View {
        ViewThatFits(in: .horizontal) {
            composerSettingsLineContent

            VStack(spacing: 9) {
                HStack(spacing: 7) {
                    Text("With")
                    agentSelectTrigger
                    Text("agent")
                }
                HStack(spacing: 7) {
                    Text("on")
                    modelSelectTrigger
                    Text("model")
                }
                if showsReasoningPicker {
                    HStack(spacing: 7) {
                        reasoningSelectTrigger
                        Text("reasoning")
                    }
                }
            }
        }
    }

    private var composerSettingsLineContent: some View {
        HStack(spacing: 7) {
            Text("With")
            agentSelectTrigger
            Text("agent on")
            modelSelectTrigger
            if showsReasoningPicker {
                Text("model,")
                reasoningSelectTrigger
                Text("reasoning")
            } else {
                Text("model")
            }
        }
    }

    @ViewBuilder
    private var newWorktreeFields: some View {
        if workspaceSelection == .createNew {
            VStack(spacing: 8) {
                TextField("Worktree name (optional)", text: $newWorkspaceName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: Capsule())
                    .frame(maxWidth: 280)
                    .accessibilityIdentifier("projects.newChat.worktree.name")

                Text("OpenCode will create a separate git worktree before sending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var projectSelectTrigger: some View {
        if request.locksProject {
            Text(selectedProject.map(projectTitle) ?? "Project")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityIdentifier("projects.newChat.project")
        } else {
            Menu {
                ForEach(viewModel.projects) { project in
                    Button {
                        selectedProjectID = project.id
                    } label: {
                        Label(projectTitle(project), systemImage: project.id == "global" ? "globe" : "folder.fill")
                    }
                }
            } label: {
                InlineSubtitleSelectTrigger(title: selectedProject.map(projectTitle) ?? "Project")
            }
            .accessibilityIdentifier("projects.newChat.project")
        }
    }

    private var workspaceSelectTrigger: some View {
        Menu {
            Button {
                workspaceSelection = .main
            } label: {
                menuSelectionLabel(workspaceTitle(selectedProject?.worktree ?? ""), isSelected: workspaceSelection == .main)
            }

            ForEach(workspaceDirectories, id: \.self) { directory in
                if directory != selectedProject?.worktree {
                    Button {
                        workspaceSelection = .directory(directory)
                    } label: {
                        menuSelectionLabel(workspaceTitle(directory), isSelected: workspaceSelection == .directory(directory))
                    }
                }
            }

            Button {
                workspaceSelection = .createNew
            } label: {
                menuSelectionLabel("Create new worktree", isSelected: workspaceSelection == .createNew)
            }
        } label: {
            InlineSubtitleSelectTrigger(title: workspaceSelectionTitle)
        }
        .accessibilityIdentifier("projects.newChat.worktree")
    }

    private var agentSelectTrigger: some View {
        Menu {
            Button {
                selectedAgentName = nil
            } label: {
                menuSelectionLabel("Default", isSelected: selectedAgentName == nil)
            }

            ForEach(viewModel.selectableAgents) { agent in
                Button {
                    selectedAgentName = agent.name
                } label: {
                    menuSelectionLabel(agent.name.capitalized, isSelected: selectedAgentName == agent.name)
                }
            }
        } label: {
            InlineSubtitleSelectTrigger(title: agentTitle)
        }
        .accessibilityIdentifier("projects.newChat.agent")
    }

    private var modelSelectTrigger: some View {
        Menu {
            Button {
                selectedModelReference = nil
                syncReasoningSelection()
            } label: {
                menuSelectionLabel(modelDefaultOptionTitle, isSelected: selectedModelReference == nil)
            }

            ForEach(viewModel.sortedProviders) { provider in
                let models = viewModel.modelConfigurationStore.visibleModels(for: provider)
                if !models.isEmpty {
                    Section(provider.name) {
                        ForEach(models, id: \.id) { model in
                            let reference = OpenCodeModelReference(providerID: provider.id, modelID: model.id)
                            Button {
                                selectedModelReference = reference
                                syncReasoningSelection()
                            } label: {
                                menuSelectionLabel(model.name, isSelected: selectedModelReference == reference)
                            }
                        }
                    }
                }
            }
        } label: {
            InlineSubtitleSelectTrigger(title: modelTitle)
        }
        .accessibilityIdentifier("projects.newChat.model")
    }

    private var reasoningSelectTrigger: some View {
        Menu {
            Button {
                selectedReasoningVariant = nil
            } label: {
                menuSelectionLabel("Default", isSelected: selectedReasoningVariant == nil)
            }

            ForEach(reasoningVariants, id: \.self) { variant in
                Button {
                    selectedReasoningVariant = variant
                } label: {
                    menuSelectionLabel(viewModel.formattedVariantTitle(variant), isSelected: selectedReasoningVariant == variant)
                }
            }
        } label: {
            InlineSubtitleSelectTrigger(title: reasoningTitle)
        }
        .accessibilityIdentifier("projects.newChat.reasoning")
    }

    @ViewBuilder
    private func menuSelectionLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var effectiveModelReference: OpenCodeModelReference? {
        selectedModelReference ?? viewModel.defaultModelReference()
    }

    private var reasoningVariants: [String] {
        viewModel.reasoningVariants(for: effectiveModelReference)
    }

    private var showsReasoningPicker: Bool {
        !reasoningVariants.isEmpty
    }

    private var agentTitle: String {
        selectedAgentName?.capitalized ?? "Default"
    }

    private var modelTitle: String {
        if let selectedModelReference,
           let model = viewModel.model(for: selectedModelReference) {
            return model.name
        }
        if let defaultModelReference = viewModel.defaultModelReference(),
           let model = viewModel.model(for: defaultModelReference) {
            return model.name
        }
        return "Default"
    }

    private var modelDefaultOptionTitle: String {
        if let defaultModelReference = viewModel.defaultModelReference(),
           let model = viewModel.model(for: defaultModelReference) {
            return "Default (\(model.name))"
        }
        return "Default"
    }

    private var reasoningTitle: String {
        selectedReasoningVariant.map(viewModel.formattedVariantTitle) ?? "Default"
    }

    private var composerSettingsSourceSignature: String {
        [
            viewModel.newSessionDefaults.agentName ?? "",
            viewModel.newSessionDefaults.providerID ?? "",
            viewModel.newSessionDefaults.modelID ?? "",
            viewModel.newSessionDefaults.reasoningVariant ?? "",
            viewModel.selectableAgents.map(\.name).joined(separator: ","),
            viewModel.sortedProviders.map { provider in
                let modelIDs = viewModel.modelConfigurationStore.visibleModels(for: provider).map(\.id).joined(separator: ",")
                return "\(provider.id):\(modelIDs)"
            }.joined(separator: "|")
        ].joined(separator: "|")
    }

    private var selectedProject: OpenCodeProject? {
        if request.locksProject, let projectID = request.projectID {
            return viewModel.projects.first { $0.id == projectID }
        }
        return viewModel.projects.first { $0.id == selectedProjectID } ?? viewModel.projects.first
    }

    private var workspaceDirectories: [String] {
        guard let selectedProject, selectedProject.id != "global" else { return [] }
        return viewModel.workspaceDirectories(for: selectedProject)
    }

    private var showsWorkspacePicker: Bool {
        guard let selectedProject else { return false }
        return viewModel.isProjectWorkspacesEnabled(for: selectedProject)
    }

    private func initializeSelectionIfNeeded() {
        guard !viewModel.projects.isEmpty else { return }
        if !hasInitializedSelection || !viewModel.projects.contains(where: { $0.id == selectedProjectID }) {
            if let projectID = request.projectID, viewModel.projects.contains(where: { $0.id == projectID }) {
                selectedProjectID = projectID
            } else {
                selectedProjectID = viewModel.currentProject?.id ?? viewModel.projects.first(where: { $0.id != "global" })?.id ?? viewModel.projects[0].id
            }
            hasInitializedSelection = true
        }
        syncWorkspaceSelection()
    }

    private func initializeComposerSettingsIfNeeded() {
        guard !hasInitializedComposerSettings else {
            syncReasoningSelection()
            return
        }

        if let requestAgentName = request.composerSelection?.agentName,
           viewModel.selectableAgents.contains(where: { $0.name == requestAgentName }) {
            selectedAgentName = requestAgentName
        } else if let defaultAgentName = viewModel.newSessionDefaults.agentName,
           viewModel.selectableAgents.contains(where: { $0.name == defaultAgentName }) {
            selectedAgentName = defaultAgentName
        } else {
            selectedAgentName = nil
        }

        selectedModelReference = request.composerSelection?.modelReference ?? viewModel.newSessionDefaultModelReference()
        selectedReasoningVariant = request.composerSelection?.reasoningVariant ?? viewModel.newSessionDefaults.reasoningVariant
        syncReasoningSelection()
        hasInitializedComposerSettings = true
    }

    private func syncReasoningSelection() {
        guard let selectedReasoningVariant else { return }
        let variants = reasoningVariants
        guard !variants.isEmpty else { return }
        guard variants.contains(selectedReasoningVariant) else {
            self.selectedReasoningVariant = nil
            return
        }
    }

    private func syncWorkspaceSelection() {
        guard let selectedProject, selectedProject.id != "global" else {
            workspaceSelection = .main
            return
        }

        let directories = workspaceDirectories
        if let directory = request.workspaceDirectory,
           !directory.isEmpty,
           !hasAppliedInitialWorkspace,
           directories.contains(where: { viewModel.workspaceKey($0) == viewModel.workspaceKey(directory) }) {
            workspaceSelection = viewModel.workspaceKey(directory) == viewModel.workspaceKey(selectedProject.worktree) ? .main : .directory(directory)
            hasAppliedInitialWorkspace = true
            return
        }

        hasAppliedInitialWorkspace = true

        switch workspaceSelection {
        case .main, .createNew:
            return
        case let .directory(directory):
            if directories.contains(where: { viewModel.workspaceKey($0) == viewModel.workspaceKey(directory) }) {
                return
            }
        }
        workspaceSelection = .main
    }

    private func startChat() {
        guard let selectedProject else { return }
        guard !isStartingChat && !viewModel.isLoading else { return }
        guard !draftStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        let workspaceDirectory = selectedProject.id == "global" ? nil : workspaceDirectoryForSelection
        let prompt = draftStore.text
        let agentMentions = draftStore.agentMentions
        let currentAttachments = attachments
        let messageID = OpenCodeIdentifier.message()
        let partID = OpenCodeIdentifier.part()

        withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
            startingSnapshot = NewSessionStartingSnapshot(
                title: visibleChatTitle,
                subtitle: startingPreviewSubtitle(for: selectedProject),
                promptPreview: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                attachmentCount: currentAttachments.count,
                phase: workspaceSelection == .createNew ? .creatingWorktree : .creatingSession
            )
            composerAccessoryExpansion = .collapsed
            isComposerMenuOpen = false
        }

        Task {
            isStartingChat = true
            defer { isStartingChat = false }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard isStartingChat, startingSnapshot != nil else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    startingSnapshot?.phase = .sendingMessage
                }
            }
            let didStart = await viewModel.startNewProjectChat(
                title: submittedChatTitle,
                prompt: prompt,
                agentMentions: agentMentions,
                attachments: currentAttachments,
                messageID: messageID,
                partID: partID,
                composerSelection: NewProjectChatComposerSelection(
                    agentName: selectedAgentName,
                    modelReference: selectedModelReference,
                    reasoningVariant: showsReasoningPicker ? selectedReasoningVariant : nil
                ),
                projectID: selectedProject.id,
                workspaceDirectory: workspaceDirectory,
                workspaceSelection: selectedProject.id == "global" ? nil : workspaceSelection,
                newWorkspaceName: newWorkspaceName
            )
            if didStart {
                withAnimation(.easeInOut(duration: 0.16)) {
                    startingSnapshot?.phase = .waitingForOpenCode
                }
                dismissSheet()
                onChatStarted()
            } else if viewModel.paywallReason != nil {
                dismissSheet()
            } else {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.02)) {
                    startingSnapshot = nil
                }
            }
        }
    }

    private func startingPreviewSubtitle(for project: OpenCodeProject) -> String {
        guard project.id != "global" else { return "Global" }
        let workspace = workspaceSelectionTitle
        return "\(projectTitle(project)) • \(workspace)"
    }

    private var workspaceDirectoryForSelection: String? {
        guard let selectedProject, selectedProject.id != "global" else { return nil }
        switch workspaceSelection {
        case .main, .createNew:
            return selectedProject.worktree
        case let .directory(directory):
            return directory.isEmpty ? selectedProject.worktree : directory
        }
    }

    private var workspaceSelectionTitle: String {
        guard let selectedProject else { return "Workspace" }
        switch workspaceSelection {
        case .main:
            return workspaceTitle(selectedProject.worktree)
        case let .directory(directory):
            return workspaceTitle(directory)
        case .createNew:
            return "New worktree"
        }
    }

    private func dismissSheet() {
        viewModel.dismissNewProjectChatSheet()
        dismiss()
    }

    private func addAttachments(_ newAttachments: [OpenCodeComposerAttachment]) {
        guard !newAttachments.isEmpty else { return }
        withAnimation(opencodeSelectionAnimation) {
            var existingIDs = Set(attachments.map(\.id))
            let uniqueAttachments = newAttachments.filter { attachment in
                guard !existingIDs.contains(attachment.id) else { return false }
                existingIDs.insert(attachment.id)
                return true
            }
            attachments.append(contentsOf: uniqueAttachments)
            if !attachments.isEmpty {
                composerAccessoryExpansion = .expanded(focus: .attachments)
            }
        }
    }

    private func removeAttachment(_ attachment: OpenCodeComposerAttachment) {
        withAnimation(opencodeSelectionAnimation) {
            attachments.removeAll { $0.id == attachment.id }
            if attachments.isEmpty {
                composerAccessoryExpansion = .collapsed
            }
        }
    }

    private func projectTitle(_ project: OpenCodeProject) -> String {
        if project.id == "global" { return "Global" }
        let trimmedName = project.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty { return trimmedName }
        return URL(fileURLWithPath: project.worktree).lastPathComponent
    }

    private func workspaceTitle(_ directory: String) -> String {
        viewModel.workspaceDisplayName(for: directory, in: selectedProject) ?? URL(fileURLWithPath: directory).lastPathComponent
    }

}

private struct NewChatInputBar: View {
    @ObservedObject var draftStore: MessageComposerDraftStore
    @Binding var isAccessoryMenuOpen: Bool
    @State private var isComposerFocused = false
    @Namespace private var glassNamespace
    let attachmentCount: Int
    let isSending: Bool
    let canSend: Bool
    let autoFocus: Bool
    let usesKeyboardBottomPadding: Bool
    let onSend: () -> Void
    let onAddAttachments: ([OpenCodeComposerAttachment]) -> Void

    var body: some View {
        MessageComposer(
            draftStore: draftStore,
            isAccessoryMenuOpen: $isAccessoryMenuOpen,
            commands: [],
            mentionableAgents: [],
            pinnedCommands: [],
            pinnedCommandNames: [],
            attachmentCount: attachmentCount,
            isBusy: false,
            canFork: false,
            forkableMessages: [],
            mcpServers: [],
            connectedMCPServerCount: 0,
            isLoadingMCP: false,
            togglingMCPServerNames: [],
            mcpErrorMessage: nil,
            onFocusChange: { isComposerFocused = $0 },
            onTextChange: { _ in },
            onAgentMentionsChange: { _ in },
            onHeightChange: { _ in },
            onSend: {
                guard canSend && !isSending else { return }
                onSend()
            },
            onStop: {},
            onSelectCommand: { _ in },
            onPinCommand: { _ in },
            onUnpinCommand: { _ in },
            onCompact: {},
            onForkMessage: { _ in },
            onLoadMCP: {},
            onToggleMCP: { _ in },
            onAddAttachments: onAddAttachments,
            glassNamespace: glassNamespace,
            allowsTextTools: false,
            allowsSessionTools: false,
            autoFocus: autoFocus
        )
        .disabled(!canSend || isSending)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, isComposerFocused || usesKeyboardBottomPadding ? 8 : 0)
        .background(.clear)
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
    static let railContentOffset: CGFloat = 22
    static let sectionTitleFont = Font.system(.footnote, design: .default).weight(.semibold)
    static let roundedSectionTitleFont = Font.system(.footnote, design: .rounded).weight(.semibold)
    static let bottomBarHeight: CGFloat = 48
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
