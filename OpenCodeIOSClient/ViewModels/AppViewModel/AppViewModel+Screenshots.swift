import Foundation

#if DEBUG
enum OpenClientScreenshotScene: String, CaseIterable {
    case connection
    case recentServers = "recent-servers"
    case projects
    case newSession = "new-session"
    case sessions
    case chat
    case permission
    case question
    case funGames = "fun-games"
    case findPlaceGame = "find-place-game"
    case findBugGame = "find-bug-game"
    case composerActions = "composer-actions"
    case providerSetup = "provider-setup"
    case paywall
    case recentWidget = "recent-widget"
    case pinnedWidget = "pinned-widget"
    case quickStartWidgets = "quick-start-widgets"
    case liveActivity = "live-activity"
    case sessionActions = "session-actions"
    case sessionPinned = "session-pinned"

    static var current: OpenClientScreenshotScene? {
        guard let rawValue = ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] else {
            return nil
        }
        return OpenClientScreenshotScene(rawValue: rawValue)
    }

    var accessibilityIdentifier: String {
        "screenshot.scene.\(rawValue)"
    }
}

extension AppViewModel {
    static func screenshot(scene: OpenClientScreenshotScene) -> AppViewModel {
        switch scene {
        case .connection:
            return screenshotConnection()
        case .recentServers:
            return screenshotRecentServers()
        case .projects:
            return screenshotProjects()
        case .newSession:
            return screenshotNewSession()
        case .sessions:
            return screenshotSessions()
        case .sessionActions:
            return screenshotSessionActions()
        case .sessionPinned:
            return screenshotSessionPinned()
        case .chat:
            return screenshotChat()
        case .permission:
            return screenshotPermission()
        case .question, .recentWidget, .pinnedWidget, .quickStartWidgets, .liveActivity:
            return screenshotQuestion()
        case .funGames:
            return screenshotFunGames()
        case .findPlaceGame:
            return screenshotFindPlaceGame()
        case .findBugGame:
            return screenshotFindBugGame()
        case .composerActions:
            return screenshotChat()
        case .providerSetup:
            return screenshotProviderSetup()
        case .paywall:
            return screenshotPaywall()
        }
    }

    private static func screenshotConnection() -> AppViewModel {
        let viewModel = AppViewModel.preview(isConnected: false, hasSavedServer: false)
        viewModel.config = OpenClientScreenshotData.secureConfig
        viewModel.errorMessage = nil
        return viewModel
    }

    private static func screenshotRecentServers() -> AppViewModel {
        let viewModel = AppViewModel.preview(isConnected: false, hasSavedServer: true, recentServerConfigs: OpenClientScreenshotData.recentServers)
        viewModel.config = OpenClientScreenshotData.recentServers[0]
        viewModel.errorMessage = nil
        return viewModel
    }

    private static func screenshotProjects() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil)
        viewModel.currentProject = nil
        viewModel.selectedDirectory = nil
        viewModel.selectedSession = nil
        return viewModel
    }

    private static func screenshotNewSession() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil)
        viewModel.currentProject = OpenClientScreenshotData.repoProject
        viewModel.selectedDirectory = OpenClientScreenshotData.repoProject.worktree
        viewModel.projectWorkspacesEnabledByScope = [
            screenshotProjectPreferenceScopeKey(
                config: viewModel.config,
                directory: OpenClientScreenshotData.repoProject.worktree
            ): true
        ]
        viewModel.newSessionDefaults = NewSessionDefaults(
            agentName: "build",
            providerID: OpenClientScreenshotData.openAIModel.providerID,
            modelID: OpenClientScreenshotData.openAIModel.id,
            reasoningVariant: "balanced"
        )
        viewModel.currentProject = nil
        viewModel.selectedDirectory = nil
        viewModel.selectedSession = nil
        viewModel.presentNewProjectChatSheet(
            projectID: OpenClientScreenshotData.repoProject.id,
            workspaceDirectory: OpenClientScreenshotData.repoProject.worktree,
            locksProject: false,
            composerSelection: NewProjectChatComposerSelection(
                agentName: "build",
                modelReference: OpenCodeModelReference(
                    providerID: OpenClientScreenshotData.openAIModel.providerID,
                    modelID: OpenClientScreenshotData.openAIModel.id
                ),
                reasoningVariant: "balanced"
            )
        )
        return viewModel
    }

    private static func screenshotProjectPreferenceScopeKey(config: OpenCodeServerConfig, directory: String?) -> String {
        [
            "server",
            config.recentServerID,
            directory ?? "global",
        ].joined(separator: "|")
    }

    private static func screenshotSessions() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil)
        viewModel.pinnedSessionIDsByScope = [viewModel.currentPinScopeKey: [OpenClientScreenshotData.releaseSession.id]]
        return viewModel
    }

    private static func screenshotSessionActions() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil)
        viewModel.projectActionsByScope = [viewModel.currentProjectPreferenceScopeKey: OpenClientScreenshotData.projectActions]
        viewModel.pinnedSessionIDsByScope = [viewModel.currentPinScopeKey: [OpenClientScreenshotData.releaseSession.id]]
        return viewModel
    }

    private static func screenshotSessionPinned() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil, sessions: OpenClientScreenshotData.pinnedSectionSessions)
        viewModel.projectActionsByScope = [viewModel.currentProjectPreferenceScopeKey: OpenClientScreenshotData.projectActions]
        viewModel.projectWorkspacesEnabledByScope = [
            screenshotProjectPreferenceScopeKey(
                config: viewModel.config,
                directory: OpenClientScreenshotData.repoProject.worktree
            ): true
        ]
        viewModel.pinnedSessionIDsByScope = [
            viewModel.currentPinScopeKey: [
                OpenClientScreenshotData.releaseSession.id,
                OpenClientScreenshotData.archivedSession.id,
                OpenClientScreenshotData.reviewSession.id,
            ]
        ]
        viewModel.workspaceSessionsByDirectory = OpenClientScreenshotData.workspaceSessionStates
        viewModel.sessionPreviews = OpenClientScreenshotData.pinnedSectionSessionPreviews
        return viewModel
    }

    private static func screenshotChat() -> AppViewModel {
        baseConnectedScreenshotViewModel(selectedSession: OpenClientScreenshotData.releaseSession)
    }

    private static func screenshotPermission() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: OpenClientScreenshotData.releaseSession)
        viewModel.permissions = [OpenClientScreenshotData.permission]
        return viewModel
    }

    private static func screenshotQuestion() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: OpenClientScreenshotData.releaseSession)
        viewModel.questions = [OpenClientScreenshotData.questionRequest]
        return viewModel
    }

    private static func screenshotFunGames() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil)
        viewModel.currentProject = nil
        viewModel.selectedDirectory = nil
        viewModel.selectedSession = nil
        viewModel.funAndGamesPreferences.showsSection = true
        return viewModel
    }

    private static func screenshotFindPlaceGame() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(
            selectedSession: OpenClientScreenshotData.findPlaceSession,
            sessions: OpenClientScreenshotData.gameSessions,
            messages: OpenClientScreenshotData.findPlaceMessages,
            todos: []
        )
        viewModel.findPlaceSessionsByID = [
            OpenClientScreenshotData.findPlaceSession.id: FindPlaceGameSession(
                sessionID: OpenClientScreenshotData.findPlaceSession.id,
                city: OpenClientScreenshotData.findPlaceCity,
                weather: FindPlaceWeatherSummary(text: "2°C / 36°F, cloudy, humidity 82%, wind 31 km/h", provider: "WeatherKit", errorDescription: nil)
            )
        ]
        viewModel.sessionPreviews = OpenClientScreenshotData.gameSessionPreviews
        return viewModel
    }

    private static func screenshotFindBugGame() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(
            selectedSession: OpenClientScreenshotData.findBugSession,
            sessions: OpenClientScreenshotData.gameSessions,
            messages: OpenClientScreenshotData.findBugMessages,
            todos: []
        )
        viewModel.findBugSessionsByID = [
            OpenClientScreenshotData.findBugSession.id: FindBugGameSession(
                sessionID: OpenClientScreenshotData.findBugSession.id,
                language: OpenClientScreenshotData.findBugLanguage
            )
        ]
        viewModel.sessionPreviews = OpenClientScreenshotData.gameSessionPreviews
        return viewModel
    }

    private static func screenshotPaywall() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: OpenClientScreenshotData.releaseSession)
        viewModel.paywallReason = .manual
#if DEBUG
        viewModel.debugEntitlementOverride = .free
#endif
        return viewModel
    }

    private static func screenshotProviderSetup() -> AppViewModel {
        let viewModel = baseConnectedScreenshotViewModel(selectedSession: nil)
        viewModel.currentProject = nil
        viewModel.selectedDirectory = nil
        viewModel.selectedSession = nil
        viewModel.allProviders = OpenClientScreenshotData.allProviders
        viewModel.availableProviders = OpenClientScreenshotData.connectedProviders
        viewModel.connectedProviderIDs = Set(OpenClientScreenshotData.connectedProviders.map(\.id))
        viewModel.defaultModelsByProviderID = OpenClientScreenshotData.providerDefaults
        viewModel.modelConfigurationStore.applyProviderAuthMethods(OpenClientScreenshotData.providerAuthMethods)
        return viewModel
    }

    private static func baseConnectedScreenshotViewModel(
        selectedSession: OpenCodeSession? = OpenClientScreenshotData.releaseSession,
        sessions: [OpenCodeSession] = OpenClientScreenshotData.sessions,
        messages: [OpenCodeMessageEnvelope] = OpenClientScreenshotData.messages,
        todos: [OpenCodeTodo] = OpenClientScreenshotData.todos
    ) -> AppViewModel {
        let viewModel = AppViewModel.preview(
            isConnected: true,
            currentProject: OpenClientScreenshotData.repoProject,
            selectedDirectory: OpenClientScreenshotData.repoProject.worktree,
            sessions: sessions,
            selectedSession: selectedSession,
            messages: messages,
            todos: todos,
            permissions: [],
            questions: [],
            sessionStatuses: [OpenClientScreenshotData.releaseSession.id: "busy"],
            draftMessage: "",
            draftAttachments: [],
            toolMessageDetails: OpenClientScreenshotData.toolMessageDetails
        )
        viewModel.config = OpenClientScreenshotData.secureConfig
        viewModel.backendMode = .server
        viewModel.errorMessage = nil
        viewModel.projects = OpenClientScreenshotData.projects
        viewModel.currentProject = OpenClientScreenshotData.repoProject
        viewModel.selectedDirectory = OpenClientScreenshotData.repoProject.worktree
        viewModel.projectWorkspacesEnabledByScope = [:]
        viewModel.sessionPreviews = OpenClientScreenshotData.sessionPreviews
        viewModel.sessionListStore.setRecentSessions(OpenClientScreenshotData.recentRepoSessions, for: OpenClientScreenshotData.repoProject.worktree)
        viewModel.sessionListStore.setRecentSessions(OpenClientScreenshotData.recentDocsSessions, for: OpenClientScreenshotData.docsProject.worktree)
        viewModel.recentServerConfigs = OpenClientScreenshotData.recentServers
        viewModel.hasSavedServer = true
        viewModel.showSavedServerPrompt = false
        viewModel.activeLiveActivitySessionIDs = [OpenClientScreenshotData.releaseSession.id]
        viewModel.allProviders = OpenClientScreenshotData.allProviders
        viewModel.availableProviders = OpenClientScreenshotData.connectedProviders
        viewModel.connectedProviderIDs = Set(OpenClientScreenshotData.connectedProviders.map(\.id))
        viewModel.defaultModelsByProviderID = OpenClientScreenshotData.providerDefaults
        viewModel.modelConfigurationStore.applyProviderAuthMethods(OpenClientScreenshotData.providerAuthMethods)
        return viewModel
    }
}

enum OpenClientScreenshotData {
    static let secureConfig = OpenCodeServerConfig(
        baseURL: "https://open-client.com/demo",
        username: "nick",
        password: "demo-token"
    )

    static let repoProject = OpenCodeProject(
        id: "screenshot-project",
        worktree: "/Users/nick/Code/openclient",
        vcs: "git",
        name: "openclient",
        sandboxes: ["/Users/nick/Code/openclient-review"],
        icon: OpenCodeProject.Icon(override: appIconDataURL, color: "#5B7CFF"),
        time: OpenCodeProject.Time(created: 1_712_200_000, updated: 1_712_286_400)
    )

    static let docsProject = OpenCodeProject(
        id: "screenshot-docs",
        worktree: "/Users/nick/Notes/product-playbook",
        vcs: nil,
        name: "product-playbook",
        sandboxes: nil,
        icon: OpenCodeProject.Icon(override: docsIconDataURL, color: "#22C55E"),
        time: OpenCodeProject.Time(created: 1_712_100_000, updated: 1_712_180_000)
    )

    static let appIconDataURL = "data:image/png;base64,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"
    static let docsIconDataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAQKADAAQAAAABAAAAQAAAAABlmWCKAAAH+UlEQVR4AeVZy29WVRCfr6WFFqEFFCx+VoTwUsGoC4yYYBSICxP/ChZGXRFj3LF2qbhQEzduXLrxERJiagRRwQUKBIiITQWCylP6+Fqs8zhzZs6993u06YP0nrb3nDMzZx6/O2fuubeVnZ/sm4QKQKVSCX9AE/otoBk9ldE1xscRKlAd0qdr8nzywdaIrvprzFbxGsdn92juaGG8aHKS4q/AJP5I0xk6k6ORhND9lWimIazDrjKpVC8d+Kwp5Yt2pflZ0Rrhk4/eepEvFDjFKS31hQHwplRI3DDDhYpRmNOHgfJuhHXY3esgIAAUsqDjQ7CAFzYIizA33F20sMuSCZwB2XQvUyaEGqAhW7orZaFnQiyClvzlAiEpgmUEIVcEywYCbwFJekv9MoEQt0BZQQhF0IdfrkzAGkDnQDoJlhOERXwObPLSspBrgmwBvPnNXloWKgixCNIOKCMI6TmghCDwFvDlr2yZELfAXILw3u79/BWHX7TIcGhxSJ/GXOOZI7197IM6r/Ak1Nq3DX3ZkyJY9AhEXbNVEyg2+QqBRvQJHFznOOkrjQOBRbwc8iVUuZI+DYhGUwGh8TkAdc0KCCGY6YKgX7FmAoRQA/RDpFcZkLwHQZAPnAW+TiMTwhbIp5BXT1k1s5lASYttmplA6xqdXqeyHWIRJH+yC2cLhNe+fpe3eP5/EegBgS2XOOZygBf/Xb/ZDcnGksZns6QIGlkrTqbYzHgmkJ3UKt0Gur/+6m+N8lvJylZACAchcSJfPb0bMm7FsDkc1qB6c8YHbPxUosBuoqF1X8yu2TIaAG8BLYER3cThAmeQ1CwFLaBiw0V8o9kN8daL+K3cEAs470vcAmUFwRVBw4mQns3t8NEr79AtDg3tkrlsCzTyipuTicPMQqbj5a2jB3FJto74/CFJqT/py1DRPkNRg0YW+mvX4k54en0VtlYfhLUre2BZVyf7e3u0Bpev34Kzl6/CyT8uwej4eHSJbZMSbvhAw+8RmVjEP5SZzmFpKucE3gI+IB9uo0zobG+HXds2wkvbN0FXZ4dGE/ve7i6gv60PrYGXn9wCA6d/gyPnLsDEf6Hy64NmFkAggFs9J8QtMBUQepZ2w769z0H//StiwPmBRbiko4NBeOLhPvj0u58sAUwEl89kJmD6N/nKpVkdiyA50AoIvRj8/ldfhJ6lXXUC8VBYhDSq4hZ5fc/z0N5WgbuYCWTPlMhkJrYDbwFU3goIuXNAIxA62tv4zlPw2mKIcaAc7Y1Bo+VdS+DEtQH48PAR3g609/VESIjomGsCXjzfaEYnAZNBAzyXKFhfk0xo4zcrvBBqNGb03JhoxCD6C7jf+1fn055EuMWBErQ3Bo0oE3ZuWh/0ik2xa2OzW0Rr7iut55goxXQceolH+AiAKNMgdaEXIlo3Frq9T21hZeGi0XGPItLiQAnaG4NGux7bAFQbUjvIoV/2yftVRJsZEDgDWgHhmY39Vu05Fr5odNxHShwkbJwYg4Lf/shaip+i414Dn0sQYgY0A+Hx/rVpNByLBaTMSIkD5WhvjM19q8PdRt48gZArglhF8AfvCPtrJbH6QC/TiBIbCVX4Ekk0iJQ4SNhRom/FcgZAuGo3FDAkKqUeP5UwX/V5VsTPFkY+B2QDLlpI1ZtaLiYm5Kgml2dJPCixbEknp75oJbKGPHcgxHNAKyAEzy24hJCPNFLiQBe4nlKfbgtrJfrcghAA8IZlrPdagbk5PAYrl3UTk1suJibkqAZWngW3R2q8BXzyiva5AwFrAIVK3lFTwzL2IAxdvQ4r70MAyNvQcjExIUetC8KlazfjFpgvEPgpwCBwFZbHEXmlTwXtf734p4StWDkQFBDumZ8RQkakxAHAmaEriR2xi7LOfpZW7GvRGomFdKU6yBmLLzwGSaixkmNnfoeRWk1idUEQITMNhBzV5JA1UhuHny8MObtiP3XW3xDhS0A2pvjqr2kOgjsIoSb6deh4pO6MjMFXP5wSAAqiJj+SxoQcNYJw+OQ5GB4bwzkZVbvS1w9I5fyaYpAMmMYgtGWNmTNesYwPnTgNF6/8Y3Fm4stMObBwsTU4Gvz7Ogz8cp5M4x/qnkcQOANaBaE2fhfe//wbuPHvsAWUiTozzYFw884IfHzoKNQmJij6eQehvfvZDQek+lNMVuLpeWDNZqO1Cfjx7EXYXF0DvfRU0ObFkZaZMmEQnyQHv/gWCASVELkgjZ1Z8pzAZ1sqYTSliCs6M77XmrXb3r1j/QHxNr9QKaliAALh+zMXgDJiXd8q6MDPY8E36cNVXaCC9+Xx0/DZwHHc97XGQeIisysa/FUNZWm2hiR0JlLpGuHrtbLqzT2T8YMCLaQ1/FGBOpojgX7DmKbCF9mlXYthx5Z1sO3RKlTxW0FP92ISgFsjozD01w04NXgJTpwfhGEEQXSYLtMrNNEb+MxU2QI++6O+qFw9X42f9b+y6o3deBKVYNhBNGxCttCc9Xy3LgOMANeYLzJqQ/qsL2a3gD8DIPBRmHyP53GeoONcm4WDbIJFqjVNkpnKeAmvsT4/1VSwBknNvuuZL2rHKOxq9NX4XoLfBi38IMSdBmQLlZIqljCk3HsJWeev3jCNZY2neunAx242QYhvg2UFwb0MFaMP9F+bBbwdQg3Q/V0+EMIWaL4PF2omxCIopax8mRA+ioaKiyjojqdRGQpjqAEWatkyIW4Bf7/LBEIogj78cm2H/wHCuCa6k6ZBVQAAAABJRU5ErkJggg=="

    static let projects = [OpenCodePreviewData.globalProject, repoProject, docsProject]

    static let releaseSession = OpenCodeSession(
        id: "session-screenshot-release",
        title: "Launch polish pass",
        workspaceID: nil,
        directory: repoProject.worktree,
        projectID: repoProject.id,
        parentID: nil
    )

    static let followupSession = OpenCodeSession(
        id: "session-screenshot-followup",
        title: "Live Activity routing",
        workspaceID: nil,
        directory: repoProject.worktree,
        projectID: repoProject.id,
        parentID: nil
    )

    static let archivedSession = OpenCodeSession(
        id: "session-screenshot-archived",
        title: "Screenshot automation",
        workspaceID: nil,
        directory: repoProject.worktree,
        projectID: repoProject.id,
        parentID: nil
    )

    static let reviewSession = OpenCodeSession(
        id: "session-screenshot-review",
        title: "PR review checklist",
        workspaceID: nil,
        directory: repoProject.worktree,
        projectID: repoProject.id,
        parentID: nil
    )

    static let sandboxSession = OpenCodeSession(
        id: "session-screenshot-sandbox",
        title: "Sandbox regression pass",
        workspaceID: nil,
        directory: repoProject.sandboxes?.first,
        projectID: repoProject.id,
        parentID: nil
    )

    static let docsSession = OpenCodeSession(
        id: "session-screenshot-docs",
        title: "Product launch notes",
        workspaceID: nil,
        directory: docsProject.worktree,
        projectID: docsProject.id,
        parentID: nil
    )

    static let sessions = [releaseSession, followupSession, archivedSession]
    static let recentRepoSessions = [releaseSession, followupSession, archivedSession, reviewSession]
    static let recentDocsSessions = [docsSession]

    static let pinnedSectionSessions = [releaseSession, followupSession, archivedSession, reviewSession]

    static let projectActions = [
        OpenCodeAction(commandName: "review", iconName: "checkmark.seal.fill"),
        OpenCodeAction(commandName: "compact", iconName: "rectangle.compress.vertical"),
    ]

    static let findPlaceSession = OpenCodeSession(
        id: "session-screenshot-find-place",
        title: "Find the Place",
        workspaceID: nil,
        directory: repoProject.worktree,
        projectID: repoProject.id,
        parentID: nil
    )

    static let findBugSession = OpenCodeSession(
        id: "session-screenshot-find-bug",
        title: "Find the Bug",
        workspaceID: nil,
        directory: repoProject.worktree,
        projectID: repoProject.id,
        parentID: nil
    )

    static let gameSessions = [findPlaceSession, findBugSession, releaseSession]

    static let findPlaceCity = FindPlaceGameCity(name: "Reykjavik", country: "Iceland", latitude: 64.1466, longitude: -21.9426)
    static let findBugLanguage = FindBugGameLanguage(id: "swift", title: "Swift")

    static let recentServers = [
        OpenCodeServerConfig(name: "Demo Cloud", iconName: "cloud.fill", baseURL: secureConfig.baseURL, username: secureConfig.username, password: secureConfig.password),
        OpenCodeServerConfig(name: "Tailscale", iconName: "network", baseURL: "http://100.92.11.7:4096", username: "nick", password: "tailnet-token"),
        OpenCodeServerConfig(iconName: "cube.box.fill", baseURL: "https://lab.open-client.com", username: "team", password: "lab-token")
    ]

    static let providerDefaults = ["openai": "gpt-5.4", "anthropic": "claude-sonnet-4.5"]

    static let openAIModel = OpenCodeModel(id: "gpt-5.4", providerID: "openai", name: "GPT-5.4", capabilities: OpenCodeModelCapabilities(reasoning: true), variants: ["balanced": .bool(true), "deep_think": .bool(true)])
    static let claudeModel = OpenCodeModel(id: "claude-sonnet-4.5", providerID: "anthropic", name: "Claude Sonnet 4.5", capabilities: OpenCodeModelCapabilities(reasoning: true), variants: ["balanced": .bool(true)])
    static let copilotModel = OpenCodeModel(id: "gpt-5-copilot", providerID: "github-copilot", name: "GPT-5 Copilot", capabilities: OpenCodeModelCapabilities(reasoning: true))
    static let googleModel = OpenCodeModel(id: "gemini-3-pro", providerID: "google", name: "Gemini 3 Pro", capabilities: OpenCodeModelCapabilities(reasoning: true))
    static let openRouterModel = OpenCodeModel(id: "openai/gpt-5.4", providerID: "openrouter", name: "GPT-5.4 via OpenRouter", capabilities: OpenCodeModelCapabilities(reasoning: true))
    static let vercelModel = OpenCodeModel(id: "v0-1.5-md", providerID: "vercel", name: "v0 1.5 Medium", capabilities: OpenCodeModelCapabilities(reasoning: false))

    static let connectedProviders = [
        OpenCodeProvider(id: "openai", name: "OpenAI", models: [openAIModel.id: openAIModel], source: "api"),
        OpenCodeProvider(id: "anthropic", name: "Anthropic", models: [claudeModel.id: claudeModel], source: "env"),
    ]

    static let allProviders = connectedProviders + [
        OpenCodeProvider(id: "github-copilot", name: "GitHub Copilot", models: [copilotModel.id: copilotModel]),
        OpenCodeProvider(id: "google", name: "Google", models: [googleModel.id: googleModel]),
        OpenCodeProvider(id: "openrouter", name: "OpenRouter", models: [openRouterModel.id: openRouterModel]),
        OpenCodeProvider(id: "vercel", name: "Vercel", models: [vercelModel.id: vercelModel]),
    ]

    static let providerAuthMethods: [String: [OpenCodeProviderAuthMethod]] = [
        "github-copilot": [OpenCodeProviderAuthMethod(type: "oauth", label: "Sign in with GitHub", prompts: nil)],
        "google": [OpenCodeProviderAuthMethod(type: "oauth", label: "Sign in with Google", prompts: nil)],
        "openrouter": [OpenCodeProviderAuthMethod(type: "api", label: "API Key", prompts: nil)],
        "vercel": [OpenCodeProviderAuthMethod(type: "oauth", label: "Sign in with Vercel", prompts: nil)],
    ]

    static let sessionPreviews: [String: SessionPreview] = [
        releaseSession.id: SessionPreview(text: "Tightened the release surface and App Store flow.", date: Date().addingTimeInterval(-180)),
        followupSession.id: SessionPreview(text: "Verified question actions route into the tracked chat.", date: Date().addingTimeInterval(-1_200)),
        archivedSession.id: SessionPreview(text: "Added deterministic screenshot scenes for launch assets.", date: Date().addingTimeInterval(-3_200)),
        docsSession.id: SessionPreview(text: "Collected provider setup notes for the next release.", date: Date().addingTimeInterval(-2_100)),
    ]

    static let pinnedSectionSessionPreviews: [String: SessionPreview] = [
        releaseSession.id: SessionPreview(text: "Running final App Store polish before the next TestFlight.", date: Date().addingTimeInterval(-120)),
        followupSession.id: SessionPreview(text: "Queued Live Activity follow-ups for later verification.", date: Date().addingTimeInterval(-840)),
        archivedSession.id: SessionPreview(text: "Pinned as the canonical screenshot automation reference.", date: Date().addingTimeInterval(-1_800)),
        reviewSession.id: SessionPreview(text: "Pinned checklist for every release candidate review.", date: Date().addingTimeInterval(-2_400)),
        sandboxSession.id: SessionPreview(text: "Workspace-only session for the review sandbox.", date: Date().addingTimeInterval(-3_600)),
    ]

    static var workspaceSessionStates: [String: OpenCodeWorkspaceSessionState] {
        var main = OpenCodeWorkspaceSessionState(isLoading: false, sessions: pinnedSectionSessions, sessionTotal: pinnedSectionSessions.count, limit: 5)
        main.sessionTotal = pinnedSectionSessions.count

        let sandboxSessions = [sandboxSession]
        let sandbox = OpenCodeWorkspaceSessionState(isLoading: false, sessions: sandboxSessions, sessionTotal: sandboxSessions.count, limit: 5)

        var states = [repoProject.worktree: main]
        if let sandboxDirectory = repoProject.sandboxes?.first {
            states[sandboxDirectory] = sandbox
        }
        return states
    }

    static let gameSessionPreviews: [String: SessionPreview] = [
        findPlaceSession.id: SessionPreview(text: "A cold North Atlantic clue narrowed the city down.", date: Date().addingTimeInterval(-120)),
        findBugSession.id: SessionPreview(text: "The hidden Swift bug is almost solved.", date: Date().addingTimeInterval(-420)),
        releaseSession.id: sessionPreviews[releaseSession.id] ?? SessionPreview(text: "Launch polish pass", date: Date().addingTimeInterval(-1_200)),
    ]

    static let todos = [
        OpenCodeTodo(content: "Finalize App Store screenshots", status: "in_progress", priority: "high"),
        OpenCodeTodo(content: "Wire GitHub Pages privacy URL", status: "pending", priority: "high"),
        OpenCodeTodo(content: "Ship first TestFlight build", status: "pending", priority: "medium"),
    ]

    static let userMessage = OpenCodeMessageEnvelope.local(
        role: "user",
        text: "Before we upload to TestFlight, can you tighten the launch polish and make the screenshots feel intentional?",
        sessionID: releaseSession.id,
        agent: "build",
        model: OpenCodeMessageModelReference(providerID: "openai", modelID: "gpt-5.4", variant: "balanced")
    )

    static let assistantMessage = OpenCodeMessageEnvelope(
        info: OpenCodeMessage(
            id: "message-screenshot-assistant",
            role: "assistant",
            sessionID: releaseSession.id,
            time: OpenCodeMessageTime(created: 1_712_286_520, completed: 1_712_286_580),
            agent: nil,
            model: OpenCodeMessageModelReference(providerID: "openai", modelID: "gpt-5.4", variant: "balanced")
        ),
        parts: [
            OpenCodePart(
                id: "part-screenshot-reasoning",
                messageID: "message-screenshot-assistant",
                sessionID: releaseSession.id,
                type: "reasoning",
                mime: nil,
                filename: nil,
                url: nil,
                reason: "completed",
                tool: nil,
                callID: nil,
                state: OpenCodeToolState(status: "completed", title: nil, error: nil, input: nil, output: nil, metadata: nil),
                text: "Making the App Store surface feel native means the screenshots need stable content, clean hierarchy, and no backend noise."
            ),
            OpenCodePart(
                id: "part-screenshot-text",
                messageID: "message-screenshot-assistant",
                sessionID: releaseSession.id,
                type: "text",
                mime: nil,
                filename: nil,
                url: nil,
                reason: nil,
                tool: nil,
                callID: nil,
                state: nil,
                text: "I added dedicated screenshot scenes so we can capture connection, sessions, chat, permissions, and questions without waiting on a live backend. From there we can reuse the same assets on the website and in App Store Connect."
            ),
        ]
    )

    static let toolMessage = OpenCodeMessageEnvelope(
        info: OpenCodeMessage(
            id: "message-screenshot-tool",
            role: "assistant",
            sessionID: releaseSession.id,
            time: OpenCodeMessageTime(created: 1_712_286_581, completed: 1_712_286_590),
            agent: nil,
            model: nil
        ),
        parts: [
            OpenCodePart(
                id: "part-screenshot-tool",
                messageID: "message-screenshot-tool",
                sessionID: releaseSession.id,
                type: "bash",
                mime: nil,
                filename: nil,
                url: nil,
                reason: "completed",
                tool: "bash",
                callID: "call-screenshot-1",
                state: OpenCodeToolState(
                    status: "completed",
                    title: "Capture screenshot scenes",
                    error: nil,
                    input: OpenCodeToolInput(
                        command: "fastlane ios screenshots",
                        description: "Captures the App Store screenshot set",
                        filePath: nil,
                        name: nil,
                        path: nil,
                        query: nil,
                        pattern: nil,
                        subagentType: nil,
                        url: nil
                    ),
                    output: "Prepared 6 deterministic scenes",
                    metadata: OpenCodeToolMetadata(output: "Prepared 6 deterministic scenes", description: "Screenshot automation", exit: 0, filediff: nil, loaded: nil, sessionId: nil, truncated: false, files: nil)
                ),
                text: nil
            )
        ]
    )

    static let messages = [userMessage, assistantMessage, toolMessage]

    static let findPlaceMessages = [
        OpenCodeMessageEnvelope.local(
            role: "user",
            text: FindPlaceGame.starterPrompt(
                city: findPlaceCity,
                weather: FindPlaceWeatherSummary(text: "2°C / 36°F, cloudy, humidity 82%, wind 31 km/h", errorDescription: nil)
            ),
            messageID: "message-find-place-setup",
            sessionID: findPlaceSession.id
        ),
        OpenCodeMessageEnvelope.local(
            role: "assistant",
            text: "I am thinking of a city. Your clue: it is cool, windy, and coastal, with volcanic landscapes nearby. Ask for a hint or make a guess.",
            messageID: "message-find-place-intro",
            sessionID: findPlaceSession.id,
            agent: "build",
            model: OpenCodeMessageModelReference(providerID: "openai", modelID: "gpt-5.4", variant: "balanced")
        ),
        OpenCodeMessageEnvelope.local(
            role: "user",
            text: "Is it Reykjavik?",
            messageID: "message-find-place-guess",
            sessionID: findPlaceSession.id
        ),
        OpenCodeMessageEnvelope.local(
            role: "assistant",
            text: FindPlaceGame.winMarker,
            messageID: "message-find-place-win",
            sessionID: findPlaceSession.id,
            agent: "build",
            model: OpenCodeMessageModelReference(providerID: "openai", modelID: "gpt-5.4", variant: "balanced")
        ),
    ]

    static let findBugMessages = [
        OpenCodeMessageEnvelope.local(
            role: "user",
            text: FindBugGame.starterPrompt(language: findBugLanguage),
            messageID: "message-find-bug-setup",
            sessionID: findBugSession.id
        ),
        OpenCodeMessageEnvelope.local(
            role: "assistant",
            text: "Find the one real bug in this Swift snippet:\n\n```swift\nfunc average(_ values: [Int]) -> Double {\n    var total = 0\n    for index in 0...values.count {\n        total += values[index]\n    }\n    return Double(total) / Double(values.count)\n}\n```\n\nTell me what breaks and why.",
            messageID: "message-find-bug-intro",
            sessionID: findBugSession.id,
            agent: "build",
            model: OpenCodeMessageModelReference(providerID: "openai", modelID: "gpt-5.4", variant: "balanced")
        ),
        OpenCodeMessageEnvelope.local(
            role: "user",
            text: "The closed range goes one past the last array index.",
            messageID: "message-find-bug-answer",
            sessionID: findBugSession.id
        ),
        OpenCodeMessageEnvelope.local(
            role: "assistant",
            text: FindBugGame.winMarker,
            messageID: "message-find-bug-win",
            sessionID: findBugSession.id,
            agent: "build",
            model: OpenCodeMessageModelReference(providerID: "openai", modelID: "gpt-5.4", variant: "balanced")
        ),
    ]

    static let permission = OpenCodePermission(
        id: "permission-screenshot-1",
        sessionID: releaseSession.id,
        permission: "write",
        patterns: ["docs/index.html"],
        always: nil,
        metadata: ["path": .string("docs/index.html")],
        tool: OpenCodePermissionTool(messageID: assistantMessage.id, callID: "call-screenshot-write")
    )

    static let questionRequest = OpenCodeQuestionRequest(
        id: "question-screenshot-1",
        sessionID: releaseSession.id,
        questions: [
            OpenCodeQuestion(
                question: "Which screen should anchor the App Store screenshots?",
                header: "Launch Assets",
                options: [
                    OpenCodeQuestionOption(label: "Chat", description: "Lead with the polished conversation view."),
                    OpenCodeQuestionOption(label: "Sessions", description: "Show the mobile session browser first."),
                    OpenCodeQuestionOption(label: "Live", description: "Feature the Live Activity and on-the-go flow."),
                ],
                multiple: false,
                custom: false
            )
        ],
        tool: OpenCodeQuestionTool(messageID: assistantMessage.id, callID: "call-screenshot-question")
    )

    static let toolMessageDetails: [String: OpenCodeMessageEnvelope] = [toolMessage.id: toolMessage]

    static let widgetServer = OpenCodeWidgetServerSnapshot(
        id: secureConfig.recentServerID,
        displayName: secureConfig.displayName,
        baseURL: secureConfig.baseURL,
        username: secureConfig.username,
        generatedAt: Date(),
        isLastConnected: true
    )

    static let recentWidgetSessions: [OpenCodeWidgetSessionSnapshot] = [
        OpenCodeWidgetSessionSnapshot(
            id: releaseSession.id,
            serverID: secureConfig.recentServerID,
            projectID: repoProject.id,
            title: releaseSession.title ?? "Launch polish pass",
            projectLabel: repoProject.name ?? "openclient",
            directory: releaseSession.directory,
            workspaceID: releaseSession.workspaceID,
            status: .needsAction,
            summaryKind: .permission,
            summaryText: permission.summary,
            updatedAt: Date().addingTimeInterval(-90),
            lastActiveAt: Date().addingTimeInterval(-90),
            isPinned: true,
            pinOrder: 0
        ),
        OpenCodeWidgetSessionSnapshot(
            id: followupSession.id,
            serverID: secureConfig.recentServerID,
            projectID: repoProject.id,
            title: followupSession.title ?? "Live Activity routing",
            projectLabel: repoProject.name ?? "openclient",
            directory: followupSession.directory,
            workspaceID: followupSession.workspaceID,
            status: .working,
            summaryKind: .snippet,
            summaryText: sessionPreviews[followupSession.id]?.text ?? "Verified Live Activity routing.",
            updatedAt: Date().addingTimeInterval(-1_200),
            lastActiveAt: Date().addingTimeInterval(-1_200),
            isPinned: false,
            pinOrder: nil
        ),
        OpenCodeWidgetSessionSnapshot(
            id: "session-screenshot-docs",
            serverID: secureConfig.recentServerID,
            projectID: docsProject.id,
            title: "Product launch notes",
            projectLabel: docsProject.name ?? "product-playbook",
            directory: docsProject.worktree,
            workspaceID: nil,
            status: .needsAction,
            summaryKind: .question,
            summaryText: questionRequest.questions.first?.question ?? "Which screen should anchor the screenshots?",
            updatedAt: Date().addingTimeInterval(-1_800),
            lastActiveAt: Date().addingTimeInterval(-1_800),
            isPinned: false,
            pinOrder: nil
        ),
        OpenCodeWidgetSessionSnapshot(
            id: archivedSession.id,
            serverID: secureConfig.recentServerID,
            projectID: repoProject.id,
            title: archivedSession.title ?? "Screenshot automation",
            projectLabel: repoProject.name ?? "openclient",
            directory: archivedSession.directory,
            workspaceID: archivedSession.workspaceID,
            status: .ready,
            summaryKind: .snippet,
            summaryText: sessionPreviews[archivedSession.id]?.text ?? "Added deterministic screenshot scenes.",
            updatedAt: Date().addingTimeInterval(-3_200),
            lastActiveAt: Date().addingTimeInterval(-3_200),
            isPinned: true,
            pinOrder: 1
        ),
    ]

    static var pinnedWidgetSessions: [OpenCodeWidgetSessionSnapshot] {
        recentWidgetSessions.filter(\.isPinned).sorted { ($0.pinOrder ?? Int.max) < ($1.pinOrder ?? Int.max) }
    }
}
#endif
