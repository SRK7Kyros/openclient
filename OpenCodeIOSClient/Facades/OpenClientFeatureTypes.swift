import Foundation

enum OpenClientSavedServerEditorMode: Equatable {
    case add
    case edit(originalServerID: String)
}

enum OpenClientProjectContentTab: String, CaseIterable {
    case sessions
    case git
    case mcp

    var title: String {
        switch self {
        case .sessions:
            return "Sessions"
        case .git:
            return "Files"
        case .mcp:
            return "MCP"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions:
            return "bubble.left.and.bubble.right"
        case .git:
            return "doc.on.doc"
        case .mcp:
            return "server.rack"
        }
    }
}

enum OpenClientStorageKey {
    static let recentServerConfigs = "recentServerConfigs"
    static let newSessionDefaults = "newSessionDefaults"
    static let appleIntelligenceWorkspaces = "appleIntelligenceWorkspaces"
    static let sessionPreviews = "sessionPreviews"
    static let pinnedSessionsByScope = "pinnedSessionsByScope"
    static let liveActivityAutoStartByScope = "liveActivityAutoStartByScope"
    static let projectWorkspacesEnabledByScope = "projectWorkspacesEnabledByScope"
    static let projectActionsByScope = "projectActionsByScope"
    static let messageDraftsByChat = "messageDraftsByChat"
    static let chatBreadcrumbs = "chatBreadcrumbs"
}
