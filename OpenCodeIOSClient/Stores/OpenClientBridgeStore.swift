import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum OpenClientBridgePhase: Equatable, Sendable {
    case idle
    case searching
    case connecting(port: Int)
    case connected(port: Int)
}

@MainActor
final class OpenClientBridgeStore: ObservableObject {
    @Published private(set) var phase: OpenClientBridgePhase = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var endpoint: OpenClientBridgeEndpoint?

    let clientID: String
    let displayName: String
    let appVersion: String
    let isEnabled: Bool

    private static let clientIDDefaultsKey = "OpenClientBridgeClientID"

    init(defaults: UserDefaults = .standard) {
        if let saved = defaults.string(forKey: Self.clientIDDefaultsKey), !saved.isEmpty {
            clientID = saved
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: Self.clientIDDefaultsKey)
            clientID = created
        }
        displayName = Self.currentDeviceName
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        isEnabled = ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] == nil
    }

    func apply(_ event: OpenClientBridgeClientEvent) {
        switch event {
        case .searching:
            phase = .searching
            errorMessage = nil
        case .connecting(let endpoint):
            phase = .connecting(port: endpoint.port)
            errorMessage = nil
            self.endpoint = endpoint
        case .connected(let endpoint):
            phase = .connected(port: endpoint.port)
            errorMessage = nil
            self.endpoint = endpoint
        case .disconnected(let message):
            phase = .idle
            errorMessage = message
        }
    }

    func reset() {
        phase = .idle
        errorMessage = nil
        endpoint = nil
    }

    private static var currentDeviceName: String {
#if canImport(UIKit)
        return UIDevice.current.name
#elseif canImport(AppKit)
        return Host.current().localizedName ?? "OpenClient for Mac"
#else
        return Host.current().localizedName ?? "OpenClient"
#endif
    }
}
