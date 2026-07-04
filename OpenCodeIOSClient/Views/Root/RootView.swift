import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    private var primarySheet: Binding<RootPrimarySheet?> {
        Binding(
            get: {
                if let request = viewModel.newProjectChatSheetRequest {
                    return .newProjectChat(request)
                }

                if isShowingConnectionSheetContent {
                    return .connection
                }

                return nil
            },
            set: { sheet in
                guard sheet == nil else { return }
                if viewModel.newProjectChatSheetRequest != nil {
                    viewModel.dismissNewProjectChatSheet()
                }
            }
        )
    }

    private var isShowingConnectionSheetContent: Bool {
        return !viewModel.isConnected || viewModel.isUsingAppleIntelligence || viewModel.isShowingConnectionOverlay
    }

    private var isShowingConnectionExperience: Bool {
        !viewModel.isConnected || viewModel.isShowingConnectionOverlay
    }

    private var shouldAutoFocusNewChatInput: Bool {
        #if DEBUG
        OpenClientScreenshotScene.current == nil
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            if isShowingConnectionExperience {
                ConnectionSheetBackdrop()
                    .transition(.opacity)
            }

            appShell
                .opacity(isShowingConnectionExperience ? 0 : 1)

            if let message = viewModel.openURLNavigationMessage {
                RootDeepLinkProgressOverlay(message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .sheet(item: primarySheet) { sheet in
            switch sheet {
            case .connection:
                ConnectionSheetView(viewModel: viewModel)
            case let .newProjectChat(request):
                ProjectNewChatSheet(viewModel: viewModel, request: request, autoFocusInput: shouldAutoFocusNewChatInput) {
                    withAnimation(opencodeSelectionAnimation) {
                        showDetailColumn()
                    }
                }
            }
        }
        .sheet(item: $viewModel.paywallReason) { reason in
            OpenClientPaywallView(viewModel: viewModel, purchaseManager: viewModel.purchaseManager, reason: reason)
        }
        .animation(.snappy(duration: 0.34, extraBounce: 0.02), value: viewModel.isShowingConnectionOverlay)
        .onChange(of: viewModel.isConnected) { _, _ in
            withAnimation(opencodeSelectionAnimation) {
                showProjectSidebarIfNeeded()
            }
        }
        .onChange(of: viewModel.isShowingConnectionOverlay) { _, isShowing in
            guard !isShowing else { return }

            withAnimation(opencodeSelectionAnimation) {
                showProjectSidebarIfNeeded()
            }
        }
        .animation(opencodeSelectionAnimation, value: viewModel.hasActiveWorkspace)
    }

    @ViewBuilder
    private var appShell: some View {
        splitShell
    }

    private var splitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            ProjectListView(viewModel: viewModel) {
                guard viewModel.currentProject != nil else { return }

                withAnimation(opencodeSelectionAnimation) {
                    showProjectContentOrDetail()
                }
            }
        } content: {
            if viewModel.currentProject == nil {
                ContentUnavailableView("Select a Project", systemImage: "folder")
            } else {
                ProjectContentView(viewModel: viewModel) {
                    withAnimation(opencodeSelectionAnimation) {
                        preferredCompactColumn = .detail
                    }
                }
            }
        } detail: {
            if viewModel.selectedProjectContentTab == .git, viewModel.hasGitProject {
                if viewModel.selectedProjectFileIsChanged {
                    GitDiffView(viewModel: viewModel)
                } else {
                    ProjectFileContentView(viewModel: viewModel)
                }
            } else if viewModel.selectedProjectContentTab == .mcp {
                ContentUnavailableView("MCP Servers", systemImage: "server.rack", description: Text("Toggle servers from the MCP tab."))
            } else if let session = viewModel.selectedSession, viewModel.isUsingAppleIntelligence == false {
                ChatRouteView(viewModel: viewModel, sessionID: session.id)
                    .equatable()
            } else {
                ContentUnavailableView("Select a Session", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .onChange(of: viewModel.selectedSession?.id) { _, sessionID in
            if sessionID != nil {
                withAnimation(opencodeSelectionAnimation) {
                    showDetailColumn()
                }
                return
            }

            guard viewModel.currentProject != nil else {
                withAnimation(opencodeSelectionAnimation) {
                    columnVisibility = .all
                    preferredCompactColumn = .sidebar
                }
                return
            }

            withAnimation(opencodeSelectionAnimation) {
                columnVisibility = .doubleColumn
                preferredCompactColumn = .content
            }
        }
        .onChange(of: viewModel.currentProject?.id) { _, projectID in
            withAnimation(opencodeSelectionAnimation) {
                if projectID == nil {
                    showProjectSidebarIfNeeded()
                } else {
                    showProjectContentOrDetail()
                }
            }
        }
        .onAppear {
            showCurrentRoute()
        }
        .animation(opencodeSelectionAnimation, value: viewModel.selectedSession?.id)
    }

    private func showCurrentRoute() {
        if viewModel.selectedSession != nil {
            showDetailColumn()
            return
        }

        guard viewModel.currentProject != nil else {
            showProjectSidebarIfNeeded()
            return
        }

        showProjectContentOrDetail()
    }

    private func showProjectSidebarIfNeeded() {
        guard viewModel.currentProject == nil, viewModel.selectedSession == nil else { return }

        columnVisibility = .all
        preferredCompactColumn = .sidebar
    }

    private func showProjectContentOrDetail() {
        if viewModel.selectedSession == nil {
            columnVisibility = .doubleColumn
            preferredCompactColumn = .content
        } else {
            showDetailColumn()
        }
    }

    private func showDetailColumn() {
        columnVisibility = horizontalSizeClass == .compact ? .detailOnly : .doubleColumn
        preferredCompactColumn = .detail
    }
}

private enum RootPrimarySheet: Identifiable {
    case connection
    case newProjectChat(NewProjectChatSheetRequest)

    var id: String {
        switch self {
        case .connection:
            return "connection"
        case let .newProjectChat(request):
            return "newProjectChat-\(request.id.uuidString)"
        }
    }
}

private struct ChatRouteView: View, Equatable {
    let viewModel: AppViewModel
    let viewModelID: ObjectIdentifier
    let sessionID: String

    init(viewModel: AppViewModel, sessionID: String) {
        self.viewModel = viewModel
        viewModelID = ObjectIdentifier(viewModel)
        self.sessionID = sessionID
    }

    nonisolated static func == (lhs: ChatRouteView, rhs: ChatRouteView) -> Bool {
        lhs.viewModelID == rhs.viewModelID && lhs.sessionID == rhs.sessionID
    }

    var body: some View {
        ChatView(viewModel: viewModel, sessionID: sessionID)
            .id(sessionID)
    }
}

private struct ConnectionSheetBackdrop: View {
    @State private var phase = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.32),
                    Color.purple.opacity(0.22),
                    Color.cyan.opacity(0.18),
                    OpenCodePlatformColor.groupedBackground,
                ],
                startPoint: phase ? .topTrailing : .topLeading,
                endPoint: phase ? .bottomLeading : .bottomTrailing
            )

            movingBlob(color: .purple, size: 360, x: phase ? -150 : 120, y: phase ? -240 : -90)
            movingBlob(color: .cyan, size: 300, x: phase ? 180 : -130, y: phase ? 80 : 220)
            movingBlob(color: .orange, size: 260, x: phase ? -80 : 170, y: phase ? 260 : 120)
        }
        .ignoresSafeArea()
        .blur(radius: 18)
        .saturation(1.15)
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private func movingBlob(color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.38), color.opacity(0.0)],
                    center: .center,
                    startRadius: 20,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .offset(x: x, y: y)
            .blendMode(.plusLighter)
    }
}

private struct RootDeepLinkProgressOverlay: View {
    let message: String

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(.top, 18)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityLabel(message)
    }
}
