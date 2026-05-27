import SwiftUI
#if canImport(UIKit)
import UIKit

#if DEBUG
struct ScreenshotSceneView: View {
    let scene: OpenClientScreenshotScene
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            screenshotContent

            Text(scene.rawValue)
                .font(.caption2)
                .foregroundStyle(.clear)
                .padding(1)
                .accessibilityIdentifier(scene.accessibilityIdentifier)
        }
        .onAppear {
            requestLandscapeForiPadScreenshots()
        }
    }

    private func requestLandscapeForiPadScreenshots() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        if #available(iOS 16.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
    }

    @ViewBuilder
    private var screenshotContent: some View {
        switch scene {
        case .connection, .recentServers:
            RootView(viewModel: viewModel)
        case .projects, .newSession, .providerSetup, .funGames, .sessions, .sessionActions, .sessionPinned, .chat, .permission, .question, .findPlaceGame, .findBugGame, .composerActions:
            RootView(viewModel: viewModel)
        case .paywall:
            OpenClientPaywallView(
                viewModel: viewModel,
                purchaseManager: viewModel.purchaseManager,
                reason: .manual
            )
        case .recentWidget:
            WidgetScreenshotDashboardView(
                title: "Recent Sessions",
                serverName: OpenClientScreenshotData.widgetServer.displayName,
                sessions: OpenClientScreenshotData.recentWidgetSessions
            )
        case .pinnedWidget:
            WidgetScreenshotDashboardView(
                title: "Pinned Sessions",
                serverName: OpenClientScreenshotData.widgetServer.displayName,
                sessions: OpenClientScreenshotData.pinnedWidgetSessions
            )
        case .quickStartWidgets:
            QuickStartWidgetScreenshotDashboardView(
                serverName: OpenClientScreenshotData.widgetServer.displayName,
                projects: OpenClientScreenshotData.projects.filter { $0.id != "global" },
                action: OpenClientScreenshotData.projectActions[0],
                model: OpenClientScreenshotData.openAIModel
            )
        case .liveActivity:
            LiveActivityScreenshotView(
                session: OpenClientScreenshotData.releaseSession,
                project: OpenClientScreenshotData.repoProject,
                permission: OpenClientScreenshotData.permission,
                question: OpenClientScreenshotData.questionRequest
            )
        }
    }

}
#endif
#endif
