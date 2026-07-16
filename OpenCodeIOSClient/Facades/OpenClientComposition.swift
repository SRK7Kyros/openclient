import Foundation

@MainActor
final class OpenClientComposition: ObservableObject {
    let viewModel: AppViewModel

    var connection: ConnectionFacade { viewModel.connectionFacade }
    var appShell: AppShellFacade { viewModel.appShellFacade }
    var projectFiles: ProjectFilesFacade { viewModel.projectFilesFacade }
    var mcp: MCPFacade { viewModel.mcpFacade }
    var commerce: CommerceFacade { viewModel.commerceFacade }
    var projects: ProjectFacade { viewModel.projectFacade }
    var sessions: SessionListFacade { viewModel.sessionListFacade }
    var chat: ChatFacade { viewModel.chatFacade }
    var configurations: ConfigurationsFacade { viewModel.configurationsFacade }
    var funAndGames: FunAndGamesFacade { viewModel.funAndGamesFacade }
    var liveActivities: LiveActivityFacade { viewModel.liveActivityFacade }

    init(viewModel: AppViewModel = AppViewModel()) {
        self.viewModel = viewModel
    }
}
