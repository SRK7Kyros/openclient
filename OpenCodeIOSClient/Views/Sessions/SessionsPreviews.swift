import SwiftUI

#if DEBUG
#Preview("Session List") {
    NavigationStack {
        SessionListPreview(viewModel: AppViewModel.preview(permissions: [OpenCodePreviewData.permission]))
    }
}

#Preview("Session Create Sheet") {
    NavigationStack {
        SessionListPreview(
            viewModel: AppViewModel.preview(isShowingCreateSessionSheet: true, draftTitle: "UI polish")
        )
    }
}

#Preview("Create Session Sheet") {
    CreateSessionPreview(viewModel: AppViewModel.preview(isShowingCreateSessionSheet: true, draftTitle: "UI polish"))
}

#Preview("Session Avatar") {
    SessionAvatar(title: "Preview polish pass")
        .padding()
}

#Preview("Session Row") {
    List {
        SessionRow(
            session: OpenCodePreviewData.primarySession,
            preview: OpenCodePreviewData.sessionPreviews[OpenCodePreviewData.primarySession.id],
            hasPermissionRequest: true
        )
    }
    .listStyle(.plain)
}

private struct SessionListPreview: View {
    @StateObject private var viewModel: AppViewModel

    init(viewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        SessionListView(facade: viewModel.sessionListFacade, onSessionChosen: {})
    }
}

private struct CreateSessionPreview: View {
    @StateObject private var viewModel: AppViewModel

    init(viewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        CreateSessionSheet(facade: viewModel.sessionListFacade)
    }
}
#endif
