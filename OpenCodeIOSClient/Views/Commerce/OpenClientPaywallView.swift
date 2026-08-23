import SwiftUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct OpenClientPaywallView: View {
    @ObservedObject var commerce: CommerceFacade
    let reason: OpenClientPaywallReason

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 12)

                PaywallAppIcon()

                VStack(spacing: 10) {
                    Text(reasonTitle)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(reasonMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    PaywallBenefitRow(
                        title: "Unlimited prompts",
                        systemImage: "paperplane.fill",
                        tint: .blue
                    )
                    PaywallBenefitRow(
                        title: "Unlimited sessions",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        tint: .purple
                    )
                    PaywallBenefitRow(
                        title: "Project Actions",
                        systemImage: "bolt.fill",
                        tint: .orange
                    )
                    PaywallBenefitRow(
                        title: "Supports the open-source app",
                        systemImage: "heart.fill",
                        tint: .pink
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .opencodeGlassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 10) {
                    Button {
                        Task { await commerce.purchaseProUnlock() }
                    } label: {
                        Text(purchaseButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Restore Purchases") {
                        Task { await commerce.restoreProUnlock() }
                    }
                    .font(.subheadline.weight(.medium))

                    if !isScreenshotScene, let error = commerce.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }

#if DEBUG
                if !isScreenshotScene {
                    OpenClientDebugEntitlementControls(commerce: commerce)
                        .padding(.top, 4)
                }
#endif

                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("OpenClient Pro")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeTrailing) {
                    Button("Done") {
                        commerce.dismissPaywall()
                    }
                }
            }
            .onChange(of: commerce.storeKitHasProUnlock) { _, unlocked in
                if unlocked {
                    commerce.dismissPaywall()
                }
            }
        }
    }

    private var purchaseButtonTitle: LocalizedStringResource {
        if isScreenshotScene {
            return "Unlock for $9.99"
        }
        if commerce.isLoadingProducts {
            return "Loading..."
        }
        if let price = commerce.proDisplayPrice {
            return LocalizedStringResource(
                "Unlock for \(price)",
                comment: "Purchase button. The variable is a StoreKit-formatted localized price."
            )
        }
        return "Unlock Pro"
    }

    private var isScreenshotScene: Bool {
        ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] == "paywall"
    }

    private var reasonTitle: LocalizedStringResource {
        switch reason {
        case .promptLimit: "Daily Prompt Limit Reached"
        case .sessionLimit: "Create Unlimited Sessions"
        case .actions: "Unlock Actions"
        case .manual: "OpenClient Pro"
        }
    }

    private var reasonMessage: LocalizedStringResource {
        switch reason {
        case .promptLimit:
            "Upgrade once to send unlimited prompts and support continued development of the open-source app."
        case .sessionLimit:
            "Free users can create one session. Upgrade once for unlimited sessions and prompts."
        case .actions:
            "Actions run project commands in temporary sessions and only surface when they need your attention."
        case .manual:
            "Unlock unlimited prompts and sessions, plus support the signed App Store build."
        }
    }

}

private struct PaywallBenefitRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.16), lineWidth: 1)
                }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

private struct PaywallAppIcon: View {
    var body: some View {
        Group {
            if let image = Self.appIconImage {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tint)
                    .padding(14)
            }
        }
        .frame(width: 82, height: 82)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .accessibilityHidden(true)
    }

    private static var appIconImage: Image? {
        let names = iconNames
        for name in names {
#if canImport(UIKit)
            if let image = UIImage(named: name) {
                return Image(uiImage: image)
            }
#elseif canImport(AppKit)
            if let image = NSImage(named: name) {
                return Image(nsImage: image)
            }
#endif
        }
        return nil
    }

    private static var iconNames: [String] {
        var names: [String] = []
        if let iconName = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String {
            names.append(iconName)
        }

        if let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files.reversed())
        }

        names.append(contentsOf: ["AppIcon", "ios-1024", "mac-1024"])
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }
}
