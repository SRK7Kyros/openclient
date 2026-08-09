import Combine
import Foundation

struct OpenClientReleaseNotes: Identifiable, Equatable {
    struct Feature: Identifiable, Equatable {
        let title: String
        let detail: String
        let systemImage: String

        var id: String { title }
    }

    let version: String
    let title: String
    let summary: String
    let features: [Feature]

    var id: String { version }
}

enum OpenClientReleaseNotesCatalog {
    static let releases = [
        OpenClientReleaseNotes(
            version: "1.0.15",
            title: "Make it yours",
            summary: "A tidier workspace, richer conversations, fresh app icons, and a smoother return to your projects.",
            features: [
                OpenClientReleaseNotes.Feature(
                    title: "Rich link previews",
                    detail: "Shared links now expand into rich, tappable previews after a message finishes streaming.",
                    systemImage: "link"
                ),
                OpenClientReleaseNotes.Feature(
                    title: "Projects, your way",
                    detail: "Use Manage Projects to drag workspaces into order or hide the ones you do not need.",
                    systemImage: "line.3.horizontal"
                ),
                OpenClientReleaseNotes.Feature(
                    title: "Make it yours",
                    detail: "Choose a new icon and decide whether chat activity gets a subtle shimmer.",
                    systemImage: "paintpalette.fill"
                ),
                OpenClientReleaseNotes.Feature(
                    title: "Connect on launch",
                    detail: "Choose a trusted saved server and OpenClient can reconnect when you open the app.",
                    systemImage: "bolt.horizontal.circle.fill"
                ),
            ]
        ),
    ]
}

enum OpenClientPluginSetup {
    static let packageName = "@openclient-ios/opencode-plugin@0.2.0"

    static let prompt = """
    Install @openclient-ios/opencode-plugin@0.2.0 in my global OpenCode configuration at ~/.config/opencode/opencode.json.

    First inspect the existing configuration. Add the package to the existing "plugin" array without removing other plugins or settings. Preserve valid JSON and the existing schema entry.

    After making the change, explain what changed and remind me to restart OpenCode. Ask before editing if the configuration location is ambiguous.
    """
}

@MainActor
final class OpenClientWhatsNewStore: ObservableObject {
    @Published private(set) var presentedRelease: OpenClientReleaseNotes?

    private static let lastOpenedVersionKey = "whatsNew.lastOpenedVersion"
    private static let lastPresentedReleaseKey = "whatsNew.lastPresentedRelease"

    private let defaults: UserDefaults
    private let currentVersion: String
    private let releases: [OpenClientReleaseNotes]

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        releases: [OpenClientReleaseNotes] = OpenClientReleaseNotesCatalog.releases,
        hasExistingConnection: Bool = false,
        checksForUpdates: Bool = true
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.releases = releases

        if checksForUpdates {
            checkForUpdate(hasExistingConnection: hasExistingConnection)
        }
    }

    var hasCurrentRelease: Bool {
        release(for: currentVersion) != nil
    }

    func dismiss() {
        presentedRelease = nil
    }

    func presentLatestRelease() {
        presentedRelease = release(for: currentVersion) ?? releases.last
    }

    private func checkForUpdate(hasExistingConnection: Bool) {
        guard !currentVersion.isEmpty else { return }

        let previousVersion = defaults.string(forKey: Self.lastOpenedVersionKey)
        defaults.set(currentVersion, forKey: Self.lastOpenedVersionKey)

        let isEligibleUpdate = if let previousVersion {
            previousVersion.compare(currentVersion, options: .numeric) == .orderedAscending
        } else {
            hasExistingConnection
        }

        guard isEligibleUpdate,
              let release = release(for: currentVersion),
              defaults.string(forKey: Self.lastPresentedReleaseKey) != release.id else { return }

        // Consume before presentation so an interrupted launch cannot show the same release twice.
        defaults.set(release.id, forKey: Self.lastPresentedReleaseKey)
        presentedRelease = release
    }

    private func release(for version: String) -> OpenClientReleaseNotes? {
        releases.first { $0.version == version }
    }
}
