import SwiftUI
import WebKit

struct OpenClientVisualHTMLActivity: Equatable {
    let payload: OpenClientVisualHTMLPayload
    let status: String
    let errorMessage: String?

    init(payload: OpenClientVisualHTMLPayload, status: String = "completed", errorMessage: String? = nil) {
        self.payload = payload
        self.status = status
        self.errorMessage = errorMessage
    }

    init?(part: OpenCodePart) {
        guard part.type == "tool",
              part.tool == "openclient_execute_tool",
              let state = part.state,
              state.input?.toolID == OpenClientVisualHTMLContract.toolID else {
            return nil
        }

        let payloadValue: OpenCodeJSONValue?
        if state.metadata?.renderer == OpenClientVisualHTMLContract.rendererID {
            payloadValue = state.metadata?.payload
        } else if let arguments = state.input?.arguments {
            payloadValue = .object(arguments)
        } else {
            payloadValue = nil
        }
        guard let payloadValue,
              let data = try? JSONEncoder().encode(payloadValue),
              let decoded = try? JSONDecoder().decode(OpenClientVisualHTMLPayload.self, from: data),
              let payload = try? decoded.validated() else {
            return nil
        }

        self.payload = payload
        status = state.status?.lowercased() ?? "pending"
        errorMessage = state.error
    }

    var isRunning: Bool {
        status == "pending" || status == "running" || status == "in_progress"
    }
}

struct OpenClientVisualHTMLView: View {
    let activity: OpenClientVisualHTMLActivity
    let onOpen: (OpenClientVisualHTMLPayload) -> Void
    let onLoad: (() -> Void)?

    init(
        activity: OpenClientVisualHTMLActivity,
        onOpen: @escaping (OpenClientVisualHTMLPayload) -> Void,
        onLoad: (() -> Void)? = nil
    ) {
        self.activity = activity
        self.onOpen = onOpen
        self.onLoad = onLoad
    }

    var body: some View {
        Button {
            onOpen(activity.payload)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .disabled(activity.isRunning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.payload.title)
        .accessibilityValue(activity.payload.accessibilityLabel)
        .accessibilityHint(
            activity.isRunning
                ? "The interactive preview will be available when rendering finishes"
                : "Opens an interactive preview with zoom and text selection"
        )
        .accessibilityIdentifier("chat.tool.visual-html")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            OpenClientVisualHTMLHeader(
                title: activity.payload.title,
                isRunning: activity.isRunning
            )
            .padding(12)

            OpenClientStaticHTMLWebView(payload: activity.payload, mode: .preview, onLoad: onLoad)
                .id(activity.payload.documentID)
                .frame(height: CGFloat(activity.payload.height))
                .clipped()
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)

            if let errorMessage = activity.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
            }
        }
        .background(OpenCodePlatformColor.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OpenClientVisualHTMLPresentation: Identifiable, Equatable {
    let payload: OpenClientVisualHTMLPayload

    var id: String { payload.documentID }
}

struct OpenClientVisualHTMLDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let payload: OpenClientVisualHTMLPayload

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(payload.accessibilityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(OpenCodePlatformColor.secondaryGroupedBackground)

                Divider()

                OpenClientStaticHTMLWebView(payload: payload, mode: .detail, onLoad: nil)
                    .id("\(payload.documentID)-detail")
                    .accessibilityIdentifier("chat.tool.visual-html.sheet")
                    .background(OpenCodePlatformColor.groupedBackground)
            }
            .navigationTitle(payload.title)
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }
}

private struct OpenClientVisualHTMLHeader: View {
    let title: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("Static HTML visual")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

enum OpenClientStaticHTMLMode: String, Sendable {
    case preview
    case detail

    var allowsInteraction: Bool { self == .detail }
}

enum OpenClientStaticHTMLDocument {
    static let contentRuleIdentifier = "openclient-static-visual-v2"
    static let contentRules = #"[{"trigger":{"url-filter":"^http://.*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https://.*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp://.*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file://.*"},"action":{"type":"block"}}]"#

    static func wrap(fragment: String, mode: OpenClientStaticHTMLMode = .preview) -> String {
        let viewport = mode.allowsInteraction
            ? "width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=5,user-scalable=yes"
            : "width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"
        let layout = mode.allowsInteraction
            ? "html, body { width: 100%; min-height: 100%; margin: 0; overflow: auto; background: transparent; }"
            : "html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }"
        let interactionCSS = mode.allowsInteraction
            ? "html, body, body * { -webkit-user-select: text !important; user-select: text !important; }"
            : ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="\(viewport)">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src 'none'; font-src 'none'; media-src 'none'; connect-src 'none'; frame-src 'none'; child-src 'none'; object-src 'none'; worker-src 'none'; manifest-src 'none'; form-action 'none'; base-uri 'none'">
        <style>
        :root { color-scheme: light dark; }
        \(layout)
        body { color: CanvasText; font: -apple-system-body; }
        * { box-sizing: border-box; }
        svg { max-width: 100%; max-height: 100%; }
        </style>
        </head>
        <body>\(fragment)<style>\(interactionCSS)</style></body>
        </html>
        """
    }
}

@MainActor
private enum OpenClientStaticHTMLRuleStore {
    private static var cachedRuleList: WKContentRuleList?
    private static var isCompiling = false
    private static var completions: [(Result<WKContentRuleList, Error>) -> Void] = []

    static func load(completion: @escaping (Result<WKContentRuleList, Error>) -> Void) {
        if let cachedRuleList {
            completion(.success(cachedRuleList))
            return
        }
        completions.append(completion)
        guard !isCompiling else { return }
        guard let store = WKContentRuleListStore.default() else {
            finish(.failure(OpenClientStaticHTMLRuleError.storeUnavailable))
            return
        }

        isCompiling = true
        store.compileContentRuleList(
            forIdentifier: OpenClientStaticHTMLDocument.contentRuleIdentifier,
            encodedContentRuleList: OpenClientStaticHTMLDocument.contentRules
        ) { ruleList, error in
            Task { @MainActor in
                if let ruleList {
                    cachedRuleList = ruleList
                    finish(.success(ruleList))
                } else {
                    finish(.failure(error ?? OpenClientStaticHTMLRuleError.compilationFailed))
                }
            }
        }
    }

    private static func finish(_ result: Result<WKContentRuleList, Error>) {
        isCompiling = false
        let pending = completions
        completions.removeAll()
        for completion in pending { completion(result) }
    }
}

private enum OpenClientStaticHTMLRuleError: LocalizedError {
    case storeUnavailable
    case compilationFailed

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            "Content rule store is unavailable"
        case .compilationFailed:
            "Content rules did not compile"
        }
    }
}

@MainActor
final class OpenClientStaticHTMLCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private var requestedDocumentID: String?
    private var allowsInitialAction = false
    private var allowsInitialResponse = false
    var didFinishLoad: (() -> Void)?
    var didFailSecureLoad: ((String) -> Void)?
    var didUpdateLoadStage: ((String) -> Void)?

    func load(
        payload: OpenClientVisualHTMLPayload,
        into webView: WKWebView,
        mode: OpenClientStaticHTMLMode = .preview
    ) {
        let requestedID = "\(payload.documentID)-\(mode.rawValue)"
        guard requestedDocumentID != requestedID else { return }
        requestedDocumentID = requestedID
        allowsInitialAction = false
        allowsInitialResponse = false
        webView.stopLoading()
        didUpdateLoadStage?("compile-rules")

        let install: @MainActor (WKContentRuleList) -> Void = { ruleList in
            guard self.requestedDocumentID == requestedID else { return }
            self.didUpdateLoadStage?("install-rules")
            webView.configuration.userContentController.removeAllContentRuleLists()
            webView.configuration.userContentController.add(ruleList)
            self.allowsInitialAction = true
            self.allowsInitialResponse = true
            self.didUpdateLoadStage?("request-load")
            webView.loadHTMLString(OpenClientStaticHTMLDocument.wrap(fragment: payload.html, mode: mode), baseURL: nil)
        }

        OpenClientStaticHTMLRuleStore.load { [weak self] result in
            switch result {
            case .success(let ruleList):
                self?.didUpdateLoadStage?("compiled-rules")
                install(ruleList)
            case .failure(let error):
                self?.didFailSecureLoad?(error.localizedDescription)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        preferences.allowsContentJavaScript = false
        didUpdateLoadStage?("navigation-action")
        let isInitialMainFrame = allowsInitialAction
            && !navigationAction.shouldPerformDownload
            && (navigationAction.request.url == nil || navigationAction.request.url?.scheme == "about")
        allowsInitialAction = false
        if !isInitialMainFrame {
            didFailSecureLoad?("Blocked unexpected navigation to \(navigationAction.request.url?.absoluteString ?? "unknown URL")")
        }
        decisionHandler(isInitialMainFrame ? .allow : .cancel, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let isInitialMainFrame = allowsInitialResponse && navigationResponse.isForMainFrame
        didUpdateLoadStage?("navigation-response")
        allowsInitialResponse = false
        if !isInitialMainFrame {
            didFailSecureLoad?("Blocked unexpected navigation response")
        }
        decisionHandler(isInitialMainFrame ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        didUpdateLoadStage?("finished")
        didFinishLoad?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        didFailSecureLoad?(error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        didFailSecureLoad?(error.localizedDescription)
    }
}

enum OpenClientStaticHTMLWebViewFactory {
    @MainActor
    static func make(
        coordinator: OpenClientStaticHTMLCoordinator,
        mode: OpenClientStaticHTMLMode = .preview
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if canImport(UIKit)
        configuration.dataDetectorTypes = []
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = mode.allowsInteraction
        webView.scrollView.bounces = mode.allowsInteraction
        webView.scrollView.alwaysBounceVertical = mode.allowsInteraction
        webView.scrollView.pinchGestureRecognizer?.isEnabled = mode.allowsInteraction
        #elseif canImport(AppKit)
        webView.allowsMagnification = mode.allowsInteraction
        #endif
        return webView
    }
}

#if canImport(UIKit)
private struct OpenClientStaticHTMLWebView: UIViewRepresentable {
    let payload: OpenClientVisualHTMLPayload
    let mode: OpenClientStaticHTMLMode
    let onLoad: (() -> Void)?

    func makeCoordinator() -> OpenClientStaticHTMLCoordinator {
        let coordinator = OpenClientStaticHTMLCoordinator()
        coordinator.didFinishLoad = onLoad
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = OpenClientStaticHTMLWebViewFactory.make(coordinator: context.coordinator, mode: mode)
        context.coordinator.load(payload: payload, into: webView, mode: mode)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.didFinishLoad = onLoad
        context.coordinator.load(payload: payload, into: webView, mode: mode)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: OpenClientStaticHTMLCoordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
#elseif canImport(AppKit)
private struct OpenClientStaticHTMLWebView: NSViewRepresentable {
    let payload: OpenClientVisualHTMLPayload
    let mode: OpenClientStaticHTMLMode
    let onLoad: (() -> Void)?

    func makeCoordinator() -> OpenClientStaticHTMLCoordinator {
        let coordinator = OpenClientStaticHTMLCoordinator()
        coordinator.didFinishLoad = onLoad
        return coordinator
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = OpenClientStaticHTMLWebViewFactory.make(coordinator: context.coordinator, mode: mode)
        context.coordinator.load(payload: payload, into: webView, mode: mode)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.didFinishLoad = onLoad
        context.coordinator.load(payload: payload, into: webView, mode: mode)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: OpenClientStaticHTMLCoordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
#endif
