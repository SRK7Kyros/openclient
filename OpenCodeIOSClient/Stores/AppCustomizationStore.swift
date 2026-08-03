import Combine
import Foundation

struct AppCustomizationPreferences: Codable, Equatable {
    var showsChatActivityShimmer: Bool
    var autoConnectServerID: String?

    init(
        showsChatActivityShimmer: Bool = true,
        autoConnectServerID: String? = nil
    ) {
        self.showsChatActivityShimmer = showsChatActivityShimmer
        self.autoConnectServerID = autoConnectServerID
    }

    private enum CodingKeys: String, CodingKey {
        case showsChatActivityShimmer
        case autoConnectServerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsChatActivityShimmer = try container.decodeIfPresent(Bool.self, forKey: .showsChatActivityShimmer) ?? true
        autoConnectServerID = try container.decodeIfPresent(String.self, forKey: .autoConnectServerID)
    }
}

@MainActor
final class AppCustomizationStore: ObservableObject {
    @Published private(set) var preferences: AppCustomizationPreferences

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "appCustomizationPreferences"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let preferences = try? JSONDecoder().decode(AppCustomizationPreferences.self, from: data) {
            self.preferences = preferences
        } else {
            preferences = AppCustomizationPreferences()
        }
    }

    var showsChatActivityShimmer: Bool {
        preferences.showsChatActivityShimmer
    }

    var autoConnectServerID: String? {
        preferences.autoConnectServerID
    }

    func setShowsChatActivityShimmer(_ shows: Bool) {
        guard preferences.showsChatActivityShimmer != shows else { return }
        preferences.showsChatActivityShimmer = shows
        persist()
    }

    func setAutoConnectServerID(_ serverID: String?) {
        guard preferences.autoConnectServerID != serverID else { return }
        preferences.autoConnectServerID = serverID
        persist()
    }

    func autoConnectServer(in servers: [OpenCodeServerConfig]) -> OpenCodeServerConfig? {
        guard let autoConnectServerID else { return nil }
        return servers.first { $0.recentServerID == autoConnectServerID }
    }

    func migrateAutoConnectServerID(from oldID: String, to newID: String) {
        guard autoConnectServerID == oldID else { return }
        setAutoConnectServerID(newID)
    }

    func reconcileAutoConnectServer(in servers: [OpenCodeServerConfig]) {
        guard let autoConnectServerID,
              !servers.contains(where: { $0.recentServerID == autoConnectServerID }) else { return }
        setAutoConnectServerID(nil)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
