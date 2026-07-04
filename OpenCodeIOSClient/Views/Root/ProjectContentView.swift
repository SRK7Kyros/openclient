import SwiftUI

struct ProjectContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onDetailChosen: () -> Void

    var body: some View {
        rootContent
        .background(OpenCodePlatformColor.groupedBackground)
        .navigationTitle(projectTitle)
        .opencodeInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .opencodeTrailing) {
                Button {
                    viewModel.presentProjectSettingsSheet()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Project Settings")
                .accessibilityIdentifier("project.settings")
            }

            if showsTopToolbarAction {
                ToolbarItem(placement: .opencodeTrailing) {
                    Button(action: toolbarAction) {
                        Image(systemName: toolbarIcon)
                    }
                    .accessibilityLabel(toolbarLabel)
                    .accessibilityIdentifier(toolbarIdentifier)
                    .disabled(toolbarDisabled)
                }
            }
        }
        .onAppear {
            syncProjectTabIfNeeded()
        }
        .sheet(isPresented: $viewModel.isShowingProjectSettingsSheet) {
            ProjectSettingsSheet(viewModel: viewModel)
        }
        .onChange(of: viewModel.currentProject?.id) { _, _ in
            syncProjectTabIfNeeded()
        }
        .onChange(of: viewModel.selectedProjectContentTab) { _, tab in
            if tab == .git {
                viewModel.presentGitView()
            } else if tab == .mcp {
                viewModel.presentMCPView()
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if usesSystemTabView {
            tabContent
        } else {
            VStack(spacing: 0) {
                ProjectContentTabSelector(
                    selection: $viewModel.selectedProjectContentTab,
                    tabs: availableTabs
                )

                content
            }
        }
    }

    private var usesSystemTabView: Bool {
        return horizontalSizeClass == .compact
    }

    private var usesNativeSearchRoleComposeTab: Bool {
#if os(iOS) || targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) {
            return horizontalSizeClass == .compact
        }
#endif

        return false
    }

    @ViewBuilder
    private var tabContent: some View {
#if os(iOS) || targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) {
            nativeRoleTabContent
        } else {
            legacyTabContent
        }
#else
        legacyTabContent
#endif
    }

    private var legacyTabContent: some View {
        TabView(selection: $viewModel.selectedProjectContentTab) {
            SessionListView(viewModel: viewModel, onSessionChosen: onDetailChosen)
                .tabItem {
                    Label(AppViewModel.ProjectContentTab.sessions.title, systemImage: AppViewModel.ProjectContentTab.sessions.systemImage)
                }
                .tag(AppViewModel.ProjectContentTab.sessions)

            if viewModel.hasGitProject {
                GitStatusView(viewModel: viewModel, onFileChosen: onDetailChosen)
                    .tabItem {
                        Label(AppViewModel.ProjectContentTab.git.title, systemImage: AppViewModel.ProjectContentTab.git.systemImage)
                    }
                    .tag(AppViewModel.ProjectContentTab.git)
            }

            MCPListView(viewModel: viewModel)
                .tabItem {
                    Label(AppViewModel.ProjectContentTab.mcp.title, systemImage: AppViewModel.ProjectContentTab.mcp.systemImage)
                }
                .tag(AppViewModel.ProjectContentTab.mcp)
        }
    }

#if os(iOS) || targetEnvironment(macCatalyst)
    @available(iOS 18.0, *)
    private var nativeRoleTabContent: some View {
        TabView(selection: nativeTabSelection) {
            Tab(
                AppViewModel.ProjectContentTab.sessions.title,
                systemImage: AppViewModel.ProjectContentTab.sessions.systemImage,
                value: ProjectNativeTab.sessions
            ) {
                SessionListView(viewModel: viewModel, onSessionChosen: onDetailChosen)
            }

            if viewModel.hasGitProject {
                Tab(
                    AppViewModel.ProjectContentTab.git.title,
                    systemImage: AppViewModel.ProjectContentTab.git.systemImage,
                    value: ProjectNativeTab.git
                ) {
                    GitStatusView(viewModel: viewModel, onFileChosen: onDetailChosen)
                }
            }

            Tab(
                AppViewModel.ProjectContentTab.mcp.title,
                systemImage: AppViewModel.ProjectContentTab.mcp.systemImage,
                value: ProjectNativeTab.mcp
            ) {
                MCPListView(viewModel: viewModel)
            }

            Tab(value: ProjectNativeTab.compose, role: .search) {
                EmptyView()
            } label: {
                Label("New", systemImage: "square.and.pencil")
                    .accessibilityLabel("Create Session")
                    .accessibilityIdentifier("sessions.create")
            }
        }
        .opencodeSearchTabSelectionActivation()
    }

    @available(iOS 18.0, *)
    private var nativeTabSelection: Binding<ProjectNativeTab> {
        Binding(
            get: { ProjectNativeTab(projectTab: viewModel.selectedProjectContentTab) },
            set: { selection in
                if selection == .compose {
                    presentCreateSessionSheet()
                } else if let projectTab = selection.projectTab {
                    viewModel.selectedProjectContentTab = projectTab
                }
            }
        )
    }
#endif

    private var showsTopToolbarAction: Bool {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            return !usesNativeSearchRoleComposeTab
        case .git, .mcp:
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            SessionListView(viewModel: viewModel, onSessionChosen: onDetailChosen)
        case .git:
            if viewModel.hasGitProject {
                GitStatusView(viewModel: viewModel, onFileChosen: onDetailChosen)
            } else {
                SessionListView(viewModel: viewModel, onSessionChosen: onDetailChosen)
            }
        case .mcp:
            MCPListView(viewModel: viewModel)
        }
    }

    private var availableTabs: [AppViewModel.ProjectContentTab] {
        AppViewModel.ProjectContentTab.allCases.filter { tab in
            tab != .git || viewModel.hasGitProject
        }
    }

    private func syncProjectTabIfNeeded() {
        if !viewModel.hasGitProject, viewModel.selectedProjectContentTab == .git {
            viewModel.selectedProjectContentTab = .sessions
        }
    }

    private var projectTitle: String {
        viewModel.projectScopeTitle.split(separator: "/").last.map(String.init) ?? viewModel.projectScopeTitle
    }

    private var toolbarIcon: String {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            return "square.and.pencil"
        case .git:
            return "arrow.clockwise"
        case .mcp:
            return "arrow.clockwise"
        }
    }

    private var toolbarLabel: String {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            return "Create Session"
        case .git:
            return viewModel.projectFilesMode == .tree ? "Refresh File Tree" : "Refresh Files"
        case .mcp:
            return "Refresh MCP Servers"
        }
    }

    private var toolbarIdentifier: String {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            return "sessions.create"
        case .git:
            return "git.refresh"
        case .mcp:
            return "mcp.refresh"
        }
    }

    private var toolbarDisabled: Bool {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            return false
        case .git:
            return viewModel.isLoadingVCS || viewModel.isLoadingFileTree
        case .mcp:
            return viewModel.isLoadingMCP
        }
    }

    private func toolbarAction() {
        switch viewModel.selectedProjectContentTab {
        case .sessions:
            presentCreateSessionSheet()
        case .git:
            Task {
                if viewModel.projectFilesMode == .tree {
                    await viewModel.reloadGitViewData(force: true)
                    await viewModel.reloadFileTree(force: true)
                } else {
                    await viewModel.reloadGitViewData(force: true)
                }
            }
        case .mcp:
            Task {
                await viewModel.reloadMCPStatus()
            }
        }
    }

    private func presentCreateSessionSheet() {
        viewModel.presentNewProjectChatSheet(
            projectID: viewModel.currentProject?.id,
            workspaceDirectory: viewModel.effectiveSelectedDirectory,
            locksProject: true
        )
    }
}

struct ProjectContentTabSelector: View {
    @Binding var selection: AppViewModel.ProjectContentTab
    let tabs: [AppViewModel.ProjectContentTab]

    var body: some View {
        Picker("Project Content", selection: $selection.animation(opencodeSelectionAnimation)) {
            ForEach(tabs, id: \.self) { tab in
                Label(tab.title, systemImage: systemImage(for: tab))
                    .labelStyle(.titleAndIcon)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func systemImage(for tab: AppViewModel.ProjectContentTab) -> String {
        tab.systemImage
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
@available(iOS 18.0, *)
private enum ProjectNativeTab: Hashable {
    case sessions
    case git
    case mcp
    case compose

    init(projectTab: AppViewModel.ProjectContentTab) {
        switch projectTab {
        case .sessions:
            self = .sessions
        case .git:
            self = .git
        case .mcp:
            self = .mcp
        }
    }

    var projectTab: AppViewModel.ProjectContentTab? {
        switch self {
        case .sessions:
            return .sessions
        case .git:
            return .git
        case .mcp:
            return .mcp
        case .compose:
            return nil
        }
    }
}
#endif

private extension AppViewModel.ProjectContentTab {
    var systemImage: String {
        switch self {
        case .sessions:
            return "bubble.left.and.bubble.right"
        case .git:
            return "doc.on.doc"
        case .mcp:
            return "server.rack"
        }
    }
}
