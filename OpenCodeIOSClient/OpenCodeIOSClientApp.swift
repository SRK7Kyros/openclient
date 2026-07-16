import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct OpenCodeIOSClientApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var composition: OpenClientComposition
#if DEBUG
    private let screenshotScene: OpenClientScreenshotScene?
#endif

    init() {
#if DEBUG
        let screenshotScene = OpenClientScreenshotScene.current
        self.screenshotScene = screenshotScene
        if let screenshotScene {
            _composition = StateObject(
                wrappedValue: OpenClientComposition(viewModel: AppViewModel.screenshot(scene: screenshotScene))
            )
        } else {
            _composition = StateObject(wrappedValue: OpenClientComposition())
        }
#else
        _composition = StateObject(wrappedValue: OpenClientComposition())
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if let screenshotScene {
                    ScreenshotSceneView(scene: screenshotScene, viewModel: composition.viewModel)
                } else {
                    rootView
                }
#else
                rootView
#endif
            }
            .opencodeSoftScrollEdgeEffect()
            .onOpenURL { url in
                composition.appShell.prepareOpenURLPresentation(url)
                Task { await composition.appShell.handleOpenURL(url) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                composition.appShell.scheduleForegroundChatCatchUp(reason: "app scene active")
            }
#if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                composition.appShell.scheduleForegroundChatCatchUp(reason: "application did become active")
            }
#endif
        }
    }

    private var rootView: some View {
        RootView(shell: composition.appShell) { sessionID, presentationRequest in
            ChatView(
                chatFacade: composition.chat,
                sessionID: sessionID,
                presentationRequest: presentationRequest
            )
        }
    }
}
