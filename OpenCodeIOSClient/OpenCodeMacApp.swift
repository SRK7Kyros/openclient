import SwiftUI

@main
struct OpenCodeMacApp: App {
    @StateObject private var composition = OpenClientComposition()

    var body: some Scene {
        WindowGroup {
            RootView(shell: composition.appShell) { sessionID, presentationRequest in
                ChatView(
                    chatFacade: composition.chat,
                    sessionID: sessionID,
                    presentationRequest: presentationRequest
                )
            }
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
    }
}
