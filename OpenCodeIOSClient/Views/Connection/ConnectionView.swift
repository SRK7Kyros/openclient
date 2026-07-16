import SwiftUI
import Combine

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(UIKit)
import UIKit
#endif

enum ConnectionSheetRoute: Hashable {
    case addServer
    case editServer(String)
    case help
    case appleIntelligenceChat(String)
}

private let connectionSheetHomeDetent: PresentationDetent = .fraction(0.98)

struct ConnectionSheetView<ChatDestination: View>: View {
    @ObservedObject var facade: ConnectionFacade
    @ObservedObject var commerce: CommerceFacade
    let chatDestination: (String) -> ChatDestination

    @State private var path: [ConnectionSheetRoute] = []
    @State private var selectedDetent: PresentationDetent = connectionSheetHomeDetent

    private var currentRoute: ConnectionSheetRoute? {
        path.last
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                ConnectionView(facade: facade, commerce: commerce) { route in
                    path.append(route)
                }
                .navigationDestination(for: ConnectionSheetRoute.self) { route in
                    destination(for: route)
                }
            }

            if facade.isShowingConnectionOverlay {
                ConnectingServerView(
                    config: facade.config,
                    phase: facade.connectionPhase,
                    cancel: { facade.cancelConnectionAttempt() },
                    retry: { facade.startConnection() },
                    edit: { facade.cancelConnectionAttempt() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .presentationDetents(detents, selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(true)
        .animation(.snappy(duration: 0.34, extraBounce: 0.02), value: facade.isShowingConnectionOverlay)
        .onAppear {
            updateDetent(for: currentRoute)
            syncAppleIntelligenceRoute()
        }
        .onChange(of: path) { oldPath, newPath in
            if case .appleIntelligenceChat = oldPath.last,
               case .appleIntelligenceChat = newPath.last {
                updateDetent(for: currentRoute)
                return
            }

            if case .appleIntelligenceChat = oldPath.last,
               facade.isUsingAppleIntelligence {
                facade.leaveAppleIntelligenceSession()
            }

            updateDetent(for: currentRoute)
        }
        .onChange(of: facade.selectedSessionID) { _, _ in
            syncAppleIntelligenceRoute()
        }
        .onChange(of: facade.isUsingAppleIntelligence) { _, _ in
            syncAppleIntelligenceRoute()
        }
    }

    private var detents: Set<PresentationDetent> {
        switch currentRoute {
        case .addServer, .editServer, .none:
            [connectionSheetHomeDetent]
        case .help, .appleIntelligenceChat:
            [.large]
        }
    }

    @ViewBuilder
    private func destination(for route: ConnectionSheetRoute) -> some View {
        switch route {
        case .addServer, .editServer:
            ServerConnectionEditorView(facade: facade)
        case .help:
            HelpView()
        case let .appleIntelligenceChat(sessionID):
            chatDestination(sessionID)
        }
    }

    private func updateDetent(for route: ConnectionSheetRoute?) {
        switch route {
        case .help, .appleIntelligenceChat:
            selectedDetent = .large
        case .addServer, .editServer, .none:
            selectedDetent = connectionSheetHomeDetent
        }
    }

    private func syncAppleIntelligenceRoute() {
        guard facade.isUsingAppleIntelligence, let sessionID = facade.selectedSessionID else {
            if case .appleIntelligenceChat = currentRoute {
                path.removeLast()
            }
            return
        }

        guard currentRoute != .appleIntelligenceChat(sessionID) else { return }
        path = [.appleIntelligenceChat(sessionID)]
    }
}

struct ConnectionView: View {
    @ObservedObject var facade: ConnectionFacade
    @ObservedObject var commerce: CommerceFacade
    var navigate: ((ConnectionSheetRoute) -> Void)? = nil

    private var hasRecentServers: Bool {
        facade.recentServerConfigs.isEmpty == false
    }

    private var isScreenshotScene: Bool {
        ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_SCENE"] != nil
    }

    var body: some View {
        connectionList
        .navigationTitle("OpenClient")
        .opencodeLargeNavigationTitle()
        .toolbar {
            if hasRecentServers {
                ToolbarItem(placement: .opencodeTrailing) {
                    Button {
                        facade.presentAddServerSheet()
                        navigate?(.addServer)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Server")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { facade.isShowingAppleIntelligenceFolderPicker },
            set: { facade.isShowingAppleIntelligenceFolderPicker = $0 }
        )) {
#if canImport(UIKit) && canImport(UniformTypeIdentifiers)
            AppleIntelligenceFolderPicker { url in
                facade.isShowingAppleIntelligenceFolderPicker = false
                guard let url else { return }
                Task { await facade.createAppleIntelligenceWorkspace(from: url) }
            }
#else
            Text("Folder picking is unavailable on this platform.")
                .presentationDetents([.medium])
#endif
        }
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var connectionList: some View {
        List {
            if hasRecentServers {
                recentServersSection

                if let errorMessage = facade.errorMessage, !errorMessage.isEmpty {
                    Section("Connection Failed") {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            if hasRecentServers == false {
                ServerConnectionSections(facade: facade)
            }

#if DEBUG
            if !isScreenshotScene {
                DebugEntitlementSection(commerce: commerce)
            }
#endif

            appleIntelligenceSection
            helpSection
        }
        .connectionListStyle(hasRecentServers: hasRecentServers)
    }

    private var recentServersSection: some View {
        Section("Recent") {
            ForEach(facade.recentServerConfigs, id: \.recentServerID) { serverConfig in
                ZStack(alignment: .topTrailing) {
                    Button {
                        facade.startConnection(to: serverConfig)
                    } label: {
                        RecentServerCard(serverConfig: serverConfig)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            facade.prepareToEditRecentServer(serverConfig)
                            navigate?(.editServer(serverConfig.recentServerID))
                        } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }

                        Button(role: .destructive) {
                            facade.removeRecentServer(serverConfig)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        facade.prepareToEditRecentServer(serverConfig)
                        navigate?(.editServer(serverConfig.recentServerID))
                    } label: {
                        Label("Edit", systemImage: "square.and.pencil")
                    }
                    .tint(.indigo)

                    Button("Remove", role: .destructive) {
                        facade.removeRecentServer(serverConfig)
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .listRowSeparator(.hidden)
#if !os(macOS)
        .listRowSpacing(0.0)
#endif
        .padding(.vertical, 0)
    }

    private var appleIntelligenceSection: some View {
        Section("Apple Intelligence") {
            Button {
                facade.presentAppleIntelligenceFolderPicker()
            } label: {
                AppleIntelligenceConnectionCard()
            }
            .buttonStyle(.plain)
            .disabled(!facade.canTryAppleIntelligence)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let summary = facade.appleIntelligenceAvailabilitySummary, !facade.canTryAppleIntelligence {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private var helpSection: some View {
        Section("Help") {
            Button {
                navigate?(.help)
            } label: {
                HelpNavigationRow()
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

private struct ServerConnectionEditorView: View {
    @ObservedObject var facade: ConnectionFacade
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ServerConnectionSections(facade: facade)
        }
        .opencodeGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(.clear)
        .navigationTitle(facade.isEditingSavedServer ? "Edit Server" : "Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if facade.isEditingSavedServer {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        facade.saveEditedServer()
                        dismiss()
                    }
                    .disabled(!facade.canSaveEditedServer)
                }
            }
        }
    }
}

struct ConnectingServerView: View {
    let config: OpenCodeServerConfig
    let phase: OpenClientConnectionPhase
    let cancel: () -> Void
    let retry: () -> Void
    let edit: () -> Void

    @State private var isAnimating = false
    @State private var elapsedSeconds = 0
    @State private var loadingWordIndex = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let loadingWords = [
        "Cogitating",
        "Musing",
        "Mulling",
        "Pondering",
        "Ruminating",
        "Contemplating",
        "Cerebrating",
        "Crafting",
        "Creating",
        "Hatching",
        "Forging",
        "Conjuring",
        "Concocting",
        "Crunching",
        "Computing",
        "Processing",
        "Inferring",
        "Generating",
        "Propagating",
        "Marinating",
        "Schlepping",
        "Booping",
        "Smooshing",
        "Honking",
        "Flibbertigibbeting",
        "Spelunking",
        "Zesting",
        "Discombobulating",
    ]

    private var isTakingLongerThanUsual: Bool {
        elapsedSeconds >= 8
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            VStack(spacing: 16) {
                serverCard
                statusBlock
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 22)

            Spacer(minLength: 24)

            actionButtons
                .frame(maxWidth: 420)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opencodeGlassSurface(in: Rectangle())
        .background(Color.black.opacity(0.04).ignoresSafeArea())
        .ignoresSafeArea()
        .onAppear {
            isAnimating = true
        }
        .onReceive(timer) { _ in
            elapsedSeconds += 1
            guard loadingWords.count > 1 else { return }
            var nextIndex = Int.random(in: 0..<loadingWords.count)
            if nextIndex == loadingWordIndex {
                nextIndex = (nextIndex + 1) % loadingWords.count
            }
            loadingWordIndex = nextIndex
        }
    }

    private var loadingWord: String {
        loadingWords[loadingWordIndex]
    }

    private var serverCard: some View {
        VStack(spacing: 14) {
            Image(systemName: config.displayIconName)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, options: .repeating, value: isAnimating)

            VStack(spacing: 6) {
                Text(config.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(config.trimmedBaseURL)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(loadingWord)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var statusBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                Text(phase.title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(phase.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if isTakingLongerThanUsual {
                Text("This is taking longer than usual. The server might be waking up, blocked by a network, or quietly contemplating existence.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(role: .cancel) {
                cancel()
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if isTakingLongerThanUsual {
                HStack(spacing: 12) {
                    Button("Try Again") {
                        retry()
                        elapsedSeconds = 0
                    }
                    .buttonStyle(.bordered)

                    Button("Edit Server") {
                        edit()
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
        }
    }
}

#if DEBUG
private struct DebugEntitlementSection: View {
    @ObservedObject var commerce: CommerceFacade

    var body: some View {
        Section {
            OpenClientDebugEntitlementControls(commerce: commerce)
                .padding(.vertical, 6)
        } header: {
            Text("Debug")
        } footer: {
            Text("Switch between free, StoreKit, unlocked, and limit-reached states while testing local builds.")
        }
    }
}
#endif

private struct ServerConnectionSections: View {
    private struct ConnectionIconOption: Identifiable {
        let symbolName: String
        let title: String

        var id: String { symbolName }
    }

    private static let iconOptions: [ConnectionIconOption] = [
        ConnectionIconOption(symbolName: "server.rack", title: "Server"),
        ConnectionIconOption(symbolName: "desktopcomputer", title: "Desktop"),
        ConnectionIconOption(symbolName: "laptopcomputer", title: "Laptop"),
        ConnectionIconOption(symbolName: "display", title: "Display"),
        ConnectionIconOption(symbolName: "iphone", title: "iPhone"),
        ConnectionIconOption(symbolName: "ipad.landscape", title: "iPad"),
        ConnectionIconOption(symbolName: "terminal", title: "Terminal"),
        ConnectionIconOption(symbolName: "network", title: "Network"),
        ConnectionIconOption(symbolName: "cloud.fill", title: "Cloud"),
        ConnectionIconOption(symbolName: "internaldrive", title: "Drive"),
        ConnectionIconOption(symbolName: "house", title: "Home"),
        ConnectionIconOption(symbolName: "cube.box.fill", title: "Lab"),
    ]

    @ObservedObject var facade: ConnectionFacade
    @State private var acknowledgesInsecureConnection = false

    private var requiresInsecureConnectionAcknowledgment: Bool {
        facade.config.usesInsecureHTTP
    }

    private var insecureConnectionMessage: String {
        switch facade.config.insecureConnectionKind {
        case .localNetwork:
            return "`http://` connections are not protected by HTTPS/TLS. This is often acceptable for local, LAN, or Tailscale-based self-hosted setups, but it is still less secure than HTTPS."
        case .nonLocal:
            return "`http://` connections are not protected by HTTPS/TLS. For non-local hosts, your credentials and traffic are better protected when the server is configured with HTTPS."
        case nil:
            return ""
        }
    }

    private var canConnect: Bool {
        !facade.isLoading && (!requiresInsecureConnectionAcknowledgment || acknowledgesInsecureConnection)
    }

    var body: some View {
        Group {
            Section {
                TextField("Name", text: $facade.config.name)
                    .accessibilityIdentifier("connection.name")

                TextField("Server URL", text: $facade.config.baseURL)
                    .opencodeDisableTextAutocapitalization()
                    .autocorrectionDisabled()
                    .opencodeURLKeyboardType()
                    .accessibilityIdentifier("connection.baseURL")

                TextField("Username", text: $facade.config.username)
                    .opencodeDisableTextAutocapitalization()
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("connection.username")

                SecureField("Password", text: $facade.config.password)
                    .accessibilityIdentifier("connection.password")

                if requiresInsecureConnectionAcknowledgment {
                    Toggle("I understand this connection is insecure", isOn: $acknowledgesInsecureConnection)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("connection.insecureAck")
                }
            } header: {
                Text("Server")
            } footer: {
                if facade.isEditingSavedServer {
                    Text("Save changes to keep this connection handy, or connect now to verify it immediately.")
                } else if requiresInsecureConnectionAcknowledgment {
                    Text(insecureConnectionMessage)
                }
            }

            if let errorMessage = facade.errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Icon") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Self.iconOptions) { option in
                            connectionIconButton(for: option)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                Button(facade.isLoading ? "Connecting..." : "Connect to OpenCode") {
                    facade.startConnectionFromEditor()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(!canConnect)
                .accessibilityIdentifier("connection.connect")
            }
        }
        .onChange(of: facade.config.trimmedBaseURL) { _, _ in
            acknowledgesInsecureConnection = false
        }
    }

    @ViewBuilder
    private func connectionIconButton(for option: ConnectionIconOption) -> some View {
        let isSelected = facade.config.displayIconName == option.symbolName

        Button {
            facade.config.iconName = option.symbolName
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : OpenCodePlatformColor.secondaryGroupedBackground)

                    Image(systemName: option.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .frame(height: 54)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                }

                Text(option.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("connection.icon.\(option.symbolName)")
        .accessibilityLabel(option.title)
    }
}

private struct ConnectionListStyleModifier: ViewModifier {
    let hasRecentServers: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content.listStyle(.inset)
#else
        if hasRecentServers {
            content
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .opencodeSoftScrollEdgeEffect()
        } else {
            content
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .opencodeSoftScrollEdgeEffect()
        }
#endif
    }
}

private extension View {
    func connectionListStyle(hasRecentServers: Bool) -> some View {
        modifier(ConnectionListStyleModifier(hasRecentServers: hasRecentServers))
    }
}

private struct HelpNavigationRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.88), Color.blue.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Help & Getting Started")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Learn what OpenCode is, how the app works, and how to connect securely.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppleIntelligenceConnectionCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.22), Color.blue.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Try with Apple Intelligence")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Try a local workspace with on-device Apple Intelligence")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Image(systemName: "arrow.up.right.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(OpenCodePlatformColor.secondaryGroupedBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#if canImport(UIKit) && canImport(UniformTypeIdentifiers)
private struct AppleIntelligenceFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
#endif

private struct RecentServerCard: View {
    let serverConfig: OpenCodeServerConfig

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: serverConfig.displayIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(serverConfig.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(serverConfig.trimmedBaseURL)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(serverConfig.trimmedUsername)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 52)

            Image(systemName: "arrow.up.right.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(OpenCodePlatformColor.secondaryGroupedBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
