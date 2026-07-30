import AVKit
import SwiftUI

struct OpenClientWhatsNewView: View {
    let release: OpenClientReleaseNotes
    let connections: [OpenCodeServerConfig]
    let activeConnectionID: String?
    let onSelectConnection: (OpenCodeServerConfig) -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 38) {
                    OpenClientWhatsNewHeader(
                        version: release.version,
                        title: release.title,
                        summary: release.summary
                    )

                    OpenClientWhatsNewBrowserSection()
                    OpenClientWhatsNewPluginSection()
                    OpenClientWhatsNewSetupSection(
                        connections: connections,
                        activeConnectionID: activeConnectionID,
                        onSelectConnection: onSelectConnection,
                        onNeedsConnection: onDone
                    )
                    OpenClientWhatsNewTerminalSection()
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .background(OpenCodePlatformColor.groupedBackground)
            .navigationTitle("What's New")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct OpenClientWhatsNewHeader: View {
    let version: String
    let title: String
    let summary: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .shadow(color: .purple.opacity(0.24), radius: 20, y: 10)
                .accessibilityHidden(true)

            Text("Version \(version)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OpenClientWhatsNewBrowserSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OpenClientWhatsNewSectionHeading(
                eyebrow: "IN-APP BROWSER",
                title: "Browse alongside OpenCode",
                detail: "Keep a website open inside your project while you make changes, refresh the result, and move between the browser and your conversation without losing context."
            )

            OpenClientBrowserWorkflowPreview()

            OpenClientBrowserButtonCallout()
        }
    }
}

private struct OpenClientBrowserButtonCallout: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.indigo, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.65), lineWidth: 3)
                        .padding(-5)
                }
                .padding(5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Open it from Sessions")
                    .font(.headline)
                Text("Tap the globe button in the top-right toolbar of a project's Sessions view.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct OpenClientBrowserWorkflowPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.yellow.opacity(0.85)).frame(width: 8, height: 8)
                Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)

                Text("preview.openclient.dev")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(10)
            .background(.quaternary.opacity(0.45))

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.indigo.opacity(0.22), .purple.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SHIP BETTER WEBSITES")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.indigo)
                        Text("Build with AI.")
                            .font(.title2.bold())
                        Text("Verify every change.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("View project")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.indigo, in: Capsule())
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(.indigo.opacity(0.28)).frame(width: 74, height: 8)
                        Capsule().fill(.quaternary).frame(width: 96, height: 7)
                        Capsule().fill(.quaternary).frame(width: 82, height: 7)
                        RoundedRectangle(cornerRadius: 6).fill(.indigo.opacity(0.72)).frame(width: 46, height: 24)
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 70)

                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenCode")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.indigo)
                        Text("Review the updated homepage")
                            .font(.caption.weight(.medium))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
            }
            .frame(height: 250)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OpenClient browser showing a website with an OpenCode instruction to review the updated homepage")
    }
}

private struct OpenClientWhatsNewPluginSection: View {
    @State private var selectedHTML: OpenClientVisualHTMLPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OpenClientWhatsNewSectionHeading(
                eyebrow: "OPENCLIENT PLUGIN",
                title: "Give OpenCode new capabilities",
                detail: "The OpenClient plugin lets OpenCode work with features inside the app, instead of only describing what to do next."
            )

            OpenClientWhatsNewCapabilityRow(
                title: "Browser automation",
                detail: "OpenCode can inspect visible content, navigate, click controls, enter text, and help verify website changes.",
                systemImage: "cursorarrow.click.2",
                tint: .blue
            )

            OpenClientWhatsNewCapabilityRow(
                title: "Visual tools",
                detail: "Charts, maps, safe HTML experiences, images, and videos can appear directly inside your conversations.",
                systemImage: "sparkles.rectangle.stack",
                tint: .purple
            )

            Text("Rendered by the same tools used in chat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            OpenClientWhatsNewImageDemo()

            OpenClientVisualChartView(activity: Self.chartActivity)

            OpenClientVisualHTMLView(activity: Self.htmlActivity) { payload in
                selectedHTML = OpenClientVisualHTMLPresentation(payload: payload)
            }

            OpenClientWhatsNewVideoDemo()
        }
        .sheet(item: $selectedHTML) { presentation in
            OpenClientVisualHTMLDetailView(payload: presentation.payload)
        }
    }

    private static let chartActivity = OpenClientVisualChartActivity(
        payload: OpenClientVisualChartPayload(
            chartType: .line,
            title: "Homepage load time",
            xAxis: OpenClientVisualChartXAxis(type: .category, title: "Build"),
            yAxis: OpenClientVisualChartYAxis(title: "Milliseconds"),
            series: [
                OpenClientVisualChartSeries(
                    id: "load-time",
                    name: "Load time",
                    points: [
                        OpenClientVisualChartPoint(id: "build-1", x: .string("1.0.9"), y: 920),
                        OpenClientVisualChartPoint(id: "build-2", x: .string("1.0.10"), y: 780),
                        OpenClientVisualChartPoint(id: "build-3", x: .string("1.0.11"), y: 690),
                        OpenClientVisualChartPoint(id: "build-4", x: .string("1.0.12"), y: 510),
                        OpenClientVisualChartPoint(id: "build-5", x: .string("1.0.13"), y: 430),
                    ]
                ),
            ]
        )
    )

    private static let htmlActivity = OpenClientVisualHTMLActivity(
        payload: OpenClientVisualHTMLPayload(
            schemaVersion: OpenClientVisualHTMLContract.schemaVersion,
            title: "Release readiness",
            accessibilityLabel: "Release readiness card showing all checks passed and ready to ship.",
            html: """
            <style>
            .card { padding: 18px; color: #172033; font-family: -apple-system; }
            .status { display: inline-block; padding: 6px 10px; border-radius: 999px; background: #d1fae5; color: #047857; font-weight: 700; font-size: 12px; }
            h2 { margin: 13px 0 6px; font-size: 22px; }
            p { margin: 0; color: #64748b; font-size: 14px; }
            .checks { display: flex; gap: 8px; margin-top: 15px; }
            .check { flex: 1; padding: 9px; border-radius: 10px; background: #eef2ff; color: #4338ca; text-align: center; font-size: 12px; font-weight: 650; }
            </style>
            <div class="card">
              <span class="status">ALL CHECKS PASSED</span>
              <h2>Ready to ship</h2>
              <p>The latest website changes are healthy.</p>
              <div class="checks"><div class="check">Build</div><div class="check">Tests</div><div class="check">Preview</div></div>
            </div>
            """,
            height: 190
        )
    )
}

private struct OpenClientWhatsNewImageDemo: View {
    private let activity = OpenClientVisualMediaDemo.imageActivity
    @StateObject private var loading: OpenClientVisualImageLoadingController

    init() {
        let activity = OpenClientVisualMediaDemo.imageActivity
        _loading = StateObject(
            wrappedValue: OpenClientVisualImageLoadingController(
                id: activity.id,
                payload: activity.payload,
                initialImage: OpenClientVisualMediaDemo.loadedImage
            )
        )
    }

    var body: some View {
        OpenClientVisualImageView(
            activity: activity,
            loading: loading,
            coordinator: nil
        )
    }
}

private struct OpenClientWhatsNewVideoDemo: View {
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                togglePlayback()
            } label: {
                if player == nil {
                    ZStack(alignment: .bottom) {
                        openClientPlatformImage(OpenClientVisualMediaDemo.preview.platformImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
                            .blur(radius: 6)
                            .scaleEffect(1.06)
                            .clipped()

                        LinearGradient(
                            colors: [.black.opacity(0.05), .black.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        OpenClientWhatsNewVideoDemoHeader(isPlaying: false, usesCoverStyle: true)
                            .padding(14)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
                } else {
                    OpenClientWhatsNewVideoDemoHeader(isPlaying: isPlaying, usesCoverStyle: false)
                        .padding(12)
                }
            }
            .buttonStyle(.plain)

            if let player {
                Divider()
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .accessibilityLabel("Website update preview video")
            }
        }
        .background(OpenCodePlatformColor.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        if let player {
            if isPlaying {
                player.pause()
            } else {
                let duration = player.currentItem?.duration.seconds ?? 0
                if duration.isFinite, duration > 0, player.currentTime().seconds >= duration - 0.1 {
                    player.seek(to: .zero)
                }
                player.play()
            }
            isPlaying.toggle()
            return
        }

        guard let url = Bundle.main.url(
            forResource: "homepage-preview",
            withExtension: "mp4",
            subdirectory: "WhatsNew"
        ) else { return }
        let player = AVPlayer(url: url)
        self.player = player
        isPlaying = true
        player.play()
    }
}

private struct OpenClientWhatsNewVideoDemoHeader: View {
    let isPlaying: Bool
    let usesCoverStyle: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 38, height: 38)
                .background(.pink.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Website update preview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(usesCoverStyle ? Color.white : Color.primary)
                Text("homepage-preview.mp4 · Local demo")
                    .font(.caption)
                    .foregroundStyle(usesCoverStyle ? Color.white.opacity(0.78) : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.pink, in: Capsule())
        }
        .contentShape(Rectangle())
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

private struct OpenClientWhatsNewSetupSection: View {
    let connections: [OpenCodeServerConfig]
    let activeConnectionID: String?
    let onSelectConnection: (OpenCodeServerConfig) -> Void
    let onNeedsConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OpenClientWhatsNewSectionHeading(
                eyebrow: "ONE-TIME SETUP",
                title: "Set up the OpenClient plugin",
                detail: "Ask OpenCode to add the plugin to your global configuration so its tools are available across projects. You review the prefilled request before anything is sent."
            )

            HStack(alignment: .top, spacing: 12) {
                Text("1")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.indigo, in: Circle())
                Text("Choose the OpenCode server you want to configure.")
                    .font(.subheadline)
            }

            HStack(alignment: .top, spacing: 12) {
                Text("2")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.purple, in: Circle())
                Text("Review and send the installation request in a new Global chat.")
                    .font(.subheadline)
            }

            if connections.isEmpty {
                Button(action: onNeedsConnection) {
                    Label("Add a Server to Continue", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                NavigationLink {
                    OpenClientWhatsNewConnectionPicker(
                        connections: connections,
                        activeConnectionID: activeConnectionID,
                        onSelectConnection: onSelectConnection
                    )
                } label: {
                    Label("Set Up with OpenCode", systemImage: "wand.and.sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("whats-new.setup-plugin")
            }

            Label(
                "Use the plugin bridge only over a trusted private network, VPN, or Tailnet. Never expose ports 4070–4090 directly to the public internet.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct OpenClientWhatsNewConnectionPicker: View {
    let connections: [OpenCodeServerConfig]
    let activeConnectionID: String?
    let onSelectConnection: (OpenCodeServerConfig) -> Void

    var body: some View {
        List(connections, id: \.recentServerID) { connection in
            Button {
                onSelectConnection(connection)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: connection.displayIconName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 40, height: 40)
                        .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(connection.displayHost)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    if activeConnectionID == connection.recentServerID {
                        Text("Connected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }

                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("whats-new.connection.\(connection.recentServerID)")
        }
        .opencodeGroupedListStyle()
        .navigationTitle("Choose a Server")
        .opencodeInlineNavigationTitle()
    }
}

private struct OpenClientWhatsNewTerminalSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OpenClientWhatsNewSectionHeading(
                eyebrow: "TERMINAL",
                title: "A terminal for every project",
                detail: "Open and manage terminal sessions directly from project navigation. Keep commands running beside your files and conversations without switching apps."
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                    Circle().fill(.yellow.opacity(0.85)).frame(width: 8, height: 8)
                    Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)
                    Spacer()
                    Text("openclient — zsh")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(.white.opacity(0.07))

                VStack(alignment: .leading, spacing: 7) {
                    Text("$ npm run build")
                        .foregroundStyle(.white)
                    Text("✓ Build completed in 1.8s")
                        .foregroundStyle(.green)
                    Text("$ _")
                        .foregroundStyle(.white)
                }
                .font(.subheadline.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(Color(red: 0.055, green: 0.07, blue: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Project terminal showing a completed build")
        }
    }
}

private struct OpenClientWhatsNewSectionHeading: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.indigo)
            Text(title)
                .font(.title2.bold())
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OpenClientWhatsNewCapabilityRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
