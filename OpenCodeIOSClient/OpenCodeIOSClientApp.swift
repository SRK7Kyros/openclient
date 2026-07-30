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
    private let videoUITestPayload: OpenClientVisualVideoPayload?
#endif

    init() {
#if DEBUG
        let screenshotScene = OpenClientScreenshotScene.current
        self.screenshotScene = screenshotScene
        if let resourceID = ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_VIDEO_RESOURCE_ID"],
           resourceID.isEmpty == false {
            let resourcePath = "/openclient/v1/video/resources/\(resourceID)/stream"
            videoUITestPayload = OpenClientVisualVideoPayload(
                schemaVersion: OpenClientVisualVideoContract.schemaVersion,
                title: "UI Test Earth Video",
                resourceID: resourceID,
                startPath: resourcePath,
                stopPath: resourcePath,
                expiresAt: "2100-01-01T00:00:00.000Z",
                file: OpenClientVisualVideoFile(
                    name: "file_example_MP4_1280_10MG.mp4",
                    sizeBytes: 9_840_497,
                    modifiedAt: "2026-07-27T19:43:25.291Z",
                    mimeType: "video/mp4"
                ),
                width: 1_280,
                height: 720,
                rotation: 0,
                duration: 30,
                cover: Self.videoUITestCover
            )
        } else {
            videoUITestPayload = nil
        }
        if let screenshotScene {
            _composition = StateObject(
                wrappedValue: OpenClientComposition(
                    viewModel: AppViewModel.screenshot(scene: screenshotScene),
                    whatsNew: OpenClientWhatsNewStore(checksForUpdates: false)
                )
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
                if let videoUITestPayload {
                    OpenClientVideoUITestView(
                        connection: composition.connection,
                        bridge: composition.bridge,
                        videoStreams: composition.videoStreams,
                        payload: videoUITestPayload
                    )
                } else if let screenshotScene {
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
        RootView(
            shell: composition.appShell,
            bridge: composition.bridge,
            whatsNew: composition.whatsNew
        ) { sessionID, presentationRequest in
            ChatView(
                chatFacade: composition.chat,
                browser: composition.appShell.browser,
                imageContent: composition.imageContent,
                videoStreams: composition.videoStreams,
                sessionID: sessionID,
                presentationRequest: presentationRequest
            )
        }
    }
}

#if DEBUG && canImport(UIKit)
private extension OpenCodeIOSClientApp {
    static let videoUITestCover: OpenClientVisualPreview = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(
            size: CGSize(width: 16, height: 9),
            format: format
        ).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        }
        return try! OpenClientVisualPreview(jpegData: data, width: 16, height: 9)
    }()
}
#endif

#if DEBUG
private struct OpenClientVideoUITestView: View {
    @ObservedObject var connection: ConnectionFacade
    @ObservedObject var bridge: OpenClientBridgeFacade
    let videoStreams: OpenClientVideoStreamCoordinator
    let payload: OpenClientVisualVideoPayload
    @StateObject private var playback: OpenClientVisualVideoPlaybackController

    init(
        connection: ConnectionFacade,
        bridge: OpenClientBridgeFacade,
        videoStreams: OpenClientVideoStreamCoordinator,
        payload: OpenClientVisualVideoPayload
    ) {
        self.connection = connection
        self.bridge = bridge
        self.videoStreams = videoStreams
        self.payload = payload
        let activity = OpenClientVisualVideoActivity(payload: payload)
        _playback = StateObject(wrappedValue: OpenClientVisualVideoPlaybackController(id: activity.id, payload: payload))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if bridge.snapshot.isConnected {
                    OpenClientVisualVideoView(
                        activity: OpenClientVisualVideoActivity(payload: payload),
                        playback: playback,
                        coordinator: videoStreams
                    )
                    Text("Video bridge ready")
                        .accessibilityIdentifier("video.ui-test.ready")
                } else {
                    ProgressView("Connecting video bridge...")
                }
            }
            .padding()
            .navigationTitle("Video Test")
        }
        .task {
            if !connection.isConnected {
                connection.startConnection()
            }
        }
    }
}
#endif
