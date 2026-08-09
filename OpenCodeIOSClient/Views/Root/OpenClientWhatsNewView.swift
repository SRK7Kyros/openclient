import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct OpenClientWhatsNewView: View {
    let release: OpenClientReleaseNotes
    @ObservedObject var connection: ConnectionFacade
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 12)

            ScrollView {
                VStack(spacing: 24) {
                    OpenClientWhatsNewHero(
                        version: release.version,
                        title: release.title,
                        summary: release.summary
                    )

                OpenClientWhatsNewFeatureList(features: release.features)
                OpenClientWhatsNewSetupSection(connection: connection)
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(OpenCodePlatformColor.groupedBackground)
        .safeAreaInset(edge: .bottom) {
            OpenClientWhatsNewFooter(onDone: onDone)
        }
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct OpenClientWhatsNewHero: View {
    let version: String
    let title: String
    let summary: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.17),
                    Color(red: 0.12, green: 0.08, blue: 0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.cyan.opacity(0.28))
                .frame(width: 170, height: 170)
                .blur(radius: 4)
                .offset(x: 62, y: -70)

            Circle()
                .fill(.purple.opacity(0.3))
                .frame(width: 130, height: 130)
                .blur(radius: 12)
                .offset(x: 44, y: 124)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("NEW IN \(version)", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())

                    Spacer(minLength: 16)

                    OpenClientWhatsNewIconStack()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)

                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, minHeight: 225, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
        .accessibilityElement(children: .combine)
    }
}

private struct OpenClientWhatsNewIconStack: View {
    var body: some View {
        HStack(spacing: -8) {
            OpenClientWhatsNewMiniIcon(systemImage: "link", tint: .cyan, rotation: -7)
            OpenClientWhatsNewMiniIcon(systemImage: "folder.fill", tint: .orange, rotation: 5)
            OpenClientWhatsNewMiniIcon(systemImage: "paintpalette.fill", tint: .purple, rotation: 9)
        }
        .accessibilityHidden(true)
    }
}

private struct OpenClientWhatsNewMiniIcon: View {
    let systemImage: String
    let tint: Color
    let rotation: Double

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.7), lineWidth: 2)
            }
            .rotationEffect(.degrees(rotation))
    }
}

private struct OpenClientWhatsNewFeatureList: View {
    let features: [OpenClientReleaseNotes.Feature]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW FEATURES")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Text("Small changes, right where they count")
                    .font(.title2.bold())
            }

            VStack(spacing: 10) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    OpenClientWhatsNewFeatureRow(feature: feature, styleIndex: index)
                }
            }
        }
    }
}

private struct OpenClientWhatsNewFeatureRow: View {
    let feature: OpenClientReleaseNotes.Feature
    let styleIndex: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(OpenCodePlatformColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.13), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch styleIndex % 4 {
        case 0: .cyan
        case 1: .orange
        case 2: .purple
        default: .green
        }
    }
}

private struct OpenClientWhatsNewFooter: View {
    let onDone: () -> Void

    var body: some View {
        Button(action: onDone) {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("new-features.continue")
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

private struct OpenClientWhatsNewSetupSection: View {
    @ObservedObject var connection: ConnectionFacade

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MAKE IT YOURS")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Text("Set up your workspace")
                    .font(.title2.bold())
            }

            OpenClientWhatsNewIconPicker(store: connection.appIconStore)

            Toggle(isOn: Binding(
                get: { connection.showsChatActivityShimmer },
                set: { connection.setShowsChatActivityShimmer($0) }
            )) {
                Label("Chat activity shimmer", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
            }
            .tint(.purple)
            .padding(16)
            .background(OpenCodePlatformColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            OpenClientWhatsNewAutoConnectPicker(connection: connection)
        }
    }
}

private struct OpenClientWhatsNewIconPicker: View {
    @ObservedObject var store: AppIconStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("App icon", systemImage: "app.dashed")
                .font(.headline)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(store.icons) { icon in
                        OpenClientWhatsNewIconOption(
                            icon: icon,
                            isSelected: icon.alternateIconName == store.selectedAlternateIconName,
                            isDisabled: store.isChangingIcon
                        ) {
                            Task { await store.select(icon) }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .background(OpenCodePlatformColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { store.refresh() }
    }
}

private struct OpenClientWhatsNewIconOption: View {
    let icon: OpenClientAppIcon
    let isSelected: Bool
    let isDisabled: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 7) {
                OpenClientWhatsNewIconArtwork(icon: icon, isSelected: isSelected, background: iconBackground)
                Text(icon.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isSelected)
        .accessibilityLabel("Use \(icon.displayName) app icon")
    }

    private var iconBackground: Color {
        isSelected ? .accentColor : .accentColor.opacity(0.12)
    }
}

private struct OpenClientWhatsNewIconArtwork: View {
    let icon: OpenClientAppIcon
    let isSelected: Bool
    let background: Color

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var fallback: some View {
        Image(systemName: icon.alternateIconName == nil ? "app.fill" : "paintpalette.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
    }

    #if canImport(UIKit)
    private var image: UIImage? {
        for file in icon.iconFiles.reversed() {
            if let path = Bundle.main.path(forResource: file, ofType: nil),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
            if let image = UIImage(named: file) {
                return image
            }
        }
        return nil
    }
    #endif
}

private struct OpenClientWhatsNewAutoConnectPicker: View {
    @ObservedObject var connection: ConnectionFacade

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect on launch", systemImage: "bolt.horizontal.circle.fill")
                .font(.headline)

            if connection.recentServerConfigs.isEmpty {
                Text("Add a server first, then choose it here to connect automatically when OpenClient opens.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Auto-Connect Server", selection: Binding(
                    get: { connection.autoConnectServerID },
                    set: { connection.setAutoConnectServerID($0) }
                )) {
                    Text("Off").tag(nil as String?)
                    ForEach(connection.recentServerConfigs, id: \.recentServerID) { server in
                        Text(server.displayName).tag(server.recentServerID as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(OpenCodePlatformColor.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

enum OpenClientVisualMediaDemo {
    static let imageData: Data = {
        guard let url = Bundle.main.url(
            forResource: "homepage-preview",
            withExtension: "jpg",
            subdirectory: "WhatsNew"
        ), let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing full-resolution visual media fixture")
        }
        return data
    }()

    static let loadedImage: OpenClientLoadedImage = {
        guard let decoded = OpenClientPlatformImageDecoder.decode(imageData),
              decoded.width == 960, decoded.height == 540 else {
            preconditionFailure("Invalid full-resolution visual media fixture")
        }
        return OpenClientLoadedImage(
            data: imageData,
            platformImage: decoded.image,
            width: decoded.width,
            height: decoded.height
        )
    }()

    static let preview: OpenClientVisualPreview = {
        guard let url = Bundle.main.url(
            forResource: "visual-media-preview",
            withExtension: "jpg",
            subdirectory: "WhatsNew"
        ), let data = try? Data(contentsOf: url) else {
            preconditionFailure("Missing visual media preview fixture")
        }
        do {
            return try OpenClientVisualPreview(jpegData: data, width: 96, height: 54)
        } catch {
            preconditionFailure("Invalid visual media preview fixture: \(error)")
        }
    }()

    static let imageActivity = OpenClientVisualImageActivity(
        payload: OpenClientVisualImagePayload(
            schemaVersion: OpenClientVisualImageContract.schemaVersion,
            title: "Updated homepage",
            accessibilityLabel: "A responsive OpenClient homepage preview.",
            resourceID: "screenshot_image_resource_000001",
            contentPath: "/openclient/v1/image/resources/screenshot_image_resource_000001/content",
            expiresAt: "2100-01-01T00:00:00.000Z",
            width: 960,
            height: 540,
            file: OpenClientVisualImageFile(
                name: "homepage-preview.jpg",
                sizeBytes: Int64(imageData.count),
                modifiedAt: "2026-07-28T00:00:00.000Z",
                mimeType: "image/jpeg"
            ),
            preview: preview
        )
    )

    static let videoPayload = OpenClientVisualVideoPayload(
        schemaVersion: OpenClientVisualVideoContract.schemaVersion,
        title: "Website update preview",
        resourceID: "screenshot_video_resource_000001",
        startPath: "/openclient/v1/video/resources/screenshot_video_resource_000001/stream",
        stopPath: "/openclient/v1/video/resources/screenshot_video_resource_000001/stream",
        expiresAt: "2100-01-01T00:00:00.000Z",
        file: OpenClientVisualVideoFile(
            name: "homepage-preview.mp4",
            sizeBytes: 35_000,
            modifiedAt: "2026-07-28T00:00:00.000Z",
            mimeType: "video/mp4"
        ),
        width: 960,
        height: 540,
        rotation: 0,
        duration: 6,
        cover: preview
    )
}
