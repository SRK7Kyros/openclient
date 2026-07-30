import SwiftUI

struct ProjectContentView: View {
    @ObservedObject var shell: AppShellFacade
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onDetailChosen: () -> Void

    private var snapshot: AppShellFacade.ProjectContentSnapshot {
        shell.projectContentSnapshot
    }

    private var selectedTab: Binding<OpenClientProjectContentTab> {
        Binding(
            get: { shell.projectContentSnapshot.selectedTab },
            set: { shell.selectProjectContentTab($0) }
        )
    }

    var body: some View {
        rootContent
        .background(OpenCodePlatformColor.groupedBackground)
        .navigationTitle(projectTitle)
        .opencodeInlineNavigationTitle()
        .toolbar {
            if showsBrowserToolbarAction {
                ToolbarItem(placement: .opencodeTrailing) {
                    Button {
                        if shell.browser.presentation == .closed {
                            shell.browser.openAddressBar()
                        } else {
                            shell.browser.expand()
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel("Open Browser")
                    .accessibilityIdentifier("browser.open")
                }
            }

            ToolbarItem(placement: .opencodeTrailing) {
                Button {
                    shell.presentProjectSettings()
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
        .sheet(isPresented: Binding(
            get: { shell.projectContentSnapshot.isShowingSettings },
            set: { shell.setProjectSettingsPresented($0) }
        )) {
            ProjectSettingsSheet(facade: shell.projects)
        }
        .onChange(of: snapshot.currentProjectID) { _, _ in
            syncProjectTabIfNeeded()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if usesSystemTabView {
            tabContent
        } else {
            VStack(spacing: 0) {
                ProjectContentTabSelector(
                    selection: selectedTab,
                    tabs: snapshot.availableTabs
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
        TabView(selection: selectedTab) {
            SessionListView(facade: shell.sessions, onSessionChosen: onDetailChosen)
                .tabItem {
                    Label(OpenClientProjectContentTab.sessions.title, systemImage: OpenClientProjectContentTab.sessions.systemImage)
                }
                .tag(OpenClientProjectContentTab.sessions)

            if snapshot.hasGitProject {
                GitStatusView(facade: shell.projectFiles, onFileChosen: onDetailChosen)
                    .tabItem {
                        Label(OpenClientProjectContentTab.git.title, systemImage: OpenClientProjectContentTab.git.systemImage)
                    }
                    .tag(OpenClientProjectContentTab.git)
            }

            if snapshot.isTerminalAvailable {
                TerminalProjectView(facade: shell.terminal, onTerminalChosen: onDetailChosen)
                    .tabItem {
                        Label(OpenClientProjectContentTab.terminal.title, systemImage: OpenClientProjectContentTab.terminal.systemImage)
                    }
                    .tag(OpenClientProjectContentTab.terminal)
            }

            MCPListView(facade: shell.mcp)
                .tabItem {
                    Label(OpenClientProjectContentTab.mcp.title, systemImage: OpenClientProjectContentTab.mcp.systemImage)
                }
                .tag(OpenClientProjectContentTab.mcp)
        }
    }

#if os(iOS) || targetEnvironment(macCatalyst)
    @available(iOS 18.0, *)
    private var nativeRoleTabContent: some View {
        TabView(selection: nativeTabSelection) {
            Tab(
                OpenClientProjectContentTab.sessions.title,
                systemImage: OpenClientProjectContentTab.sessions.systemImage,
                value: ProjectNativeTab.sessions
            ) {
                SessionListView(facade: shell.sessions, onSessionChosen: onDetailChosen)
            }

            if snapshot.hasGitProject {
                Tab(
                    OpenClientProjectContentTab.git.title,
                    systemImage: OpenClientProjectContentTab.git.systemImage,
                    value: ProjectNativeTab.git
                ) {
                    GitStatusView(facade: shell.projectFiles, onFileChosen: onDetailChosen)
                }
            }


            if snapshot.isTerminalAvailable {
                Tab(
                    OpenClientProjectContentTab.terminal.title,
                    systemImage: OpenClientProjectContentTab.terminal.systemImage,
                    value: ProjectNativeTab.terminal
                ) {
                    TerminalProjectView(facade: shell.terminal, onTerminalChosen: onDetailChosen)
                }
            }

            Tab(
                OpenClientProjectContentTab.mcp.title,
                systemImage: OpenClientProjectContentTab.mcp.systemImage,
                value: ProjectNativeTab.mcp
            ) {
                MCPListView(facade: shell.mcp)
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
        .opencodeProjectBrowserAccessory(browser: shell.browser)
    }

    @available(iOS 18.0, *)
    private var nativeTabSelection: Binding<ProjectNativeTab> {
        Binding(
            get: { ProjectNativeTab(projectTab: snapshot.selectedTab) },
            set: { selection in
                if selection == .compose {
                    presentCreateSessionSheet()
                } else if let projectTab = selection.projectTab {
                    shell.selectProjectContentTab(projectTab)
                }
            }
        )
    }
#endif

    private var showsTopToolbarAction: Bool {
        snapshot.showsToolbarAction(usesNativeComposeTab: usesNativeSearchRoleComposeTab)
    }

    private var showsBrowserToolbarAction: Bool {
        #if os(iOS) || targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.selectedTab {
        case .sessions:
            SessionListView(facade: shell.sessions, onSessionChosen: onDetailChosen)
        case .git:
            if snapshot.hasGitProject {
                GitStatusView(facade: shell.projectFiles, onFileChosen: onDetailChosen)
            } else {
                SessionListView(facade: shell.sessions, onSessionChosen: onDetailChosen)
            }
        case .mcp:
            MCPListView(facade: shell.mcp)
        case .terminal:
            if snapshot.isTerminalAvailable {
                TerminalProjectView(facade: shell.terminal, onTerminalChosen: onDetailChosen)
            } else {
                SessionListView(facade: shell.sessions, onSessionChosen: onDetailChosen)
            }
        }
    }

    private func syncProjectTabIfNeeded() {
        shell.reconcileInvalidGitSelection()
    }

    private var projectTitle: String {
        snapshot.title
    }

    private var toolbarIcon: String {
        snapshot.toolbarIcon
    }

    private var toolbarLabel: String {
        snapshot.toolbarLabel
    }

    private var toolbarIdentifier: String {
        snapshot.toolbarIdentifier
    }

    private var toolbarDisabled: Bool {
        snapshot.isToolbarDisabled
    }

    private func toolbarAction() {
        shell.performProjectContentToolbarAction()
    }

    private func presentCreateSessionSheet() {
        shell.presentNewChatForCurrentContext()
    }
}

struct ProjectContentTabSelector: View {
    @Binding var selection: OpenClientProjectContentTab
    let tabs: [OpenClientProjectContentTab]

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

    private func systemImage(for tab: OpenClientProjectContentTab) -> String {
        tab.systemImage
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
@available(iOS 18.0, *)
private enum ProjectNativeTab: Hashable {
    case sessions
    case git
    case terminal
    case mcp
    case compose

    init(projectTab: OpenClientProjectContentTab) {
        switch projectTab {
        case .sessions:
            self = .sessions
        case .git:
            self = .git
        case .mcp:
            self = .mcp
        case .terminal:
            self = .terminal
        }
    }

    var projectTab: OpenClientProjectContentTab? {
        switch self {
        case .sessions:
            return .sessions
        case .git:
            return .git
        case .mcp:
            return .mcp
        case .terminal:
            return .terminal
        case .compose:
            return nil
        }
    }
}
#endif
