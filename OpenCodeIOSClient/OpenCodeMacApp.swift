import SwiftUI

@main
struct OpenCodeMacApp: App {
    @StateObject private var composition = OpenClientComposition()

    var body: some Scene {
        WindowGroup {
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
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
    }
}
