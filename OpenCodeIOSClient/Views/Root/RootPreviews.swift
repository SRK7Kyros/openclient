import SwiftUI

#if DEBUG
#Preview("Disconnected") {
    let viewModel = AppViewModel.preview(isConnected: false)
    RootView(shell: viewModel.appShellFacade) { sessionID, presentationRequest in
        ChatView(
            chatFacade: viewModel.chatFacade,
            browser: viewModel.appShellFacade.browser,
            sessionID: sessionID,
            presentationRequest: presentationRequest
        )
    }
}

#Preview("Connected") {
    let viewModel = AppViewModel.preview()
    RootView(shell: viewModel.appShellFacade) { sessionID, presentationRequest in
        ChatView(
            chatFacade: viewModel.chatFacade,
            browser: viewModel.appShellFacade.browser,
            sessionID: sessionID,
            presentationRequest: presentationRequest
        )
    }
}
#endif
