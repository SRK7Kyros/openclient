import XCTest
import UIKit
import WebKit
@testable import OpenClient

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testAddressResolverPreservesExplicitWebURL() {
        XCTAssertEqual(
            BrowserAddressResolver.resolve("https://opencode.ai/docs")?.absoluteString,
            "https://opencode.ai/docs"
        )
    }

    func testAddressResolverAddsHTTPSForDomain() {
        XCTAssertEqual(
            BrowserAddressResolver.resolve("opencode.ai/docs")?.absoluteString,
            "https://opencode.ai/docs"
        )
    }

    func testAddressResolverUsesHTTPForLocalhost() {
        XCTAssertEqual(
            BrowserAddressResolver.resolve("localhost:3000")?.absoluteString,
            "http://localhost:3000"
        )
    }

    func testAddressResolverTurnsWordsIntoSearch() {
        let url = BrowserAddressResolver.resolve("OpenCode browser plugin")
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }

        XCTAssertEqual(components?.host, "www.google.com")
        XCTAssertEqual(components?.path, "/search")
        XCTAssertEqual(components?.queryItems, [URLQueryItem(name: "q", value: "OpenCode browser plugin")])
    }

    func testPresentationTransitionsPreserveFocusIntentWhenExpandingCollapsedBrowser() {
        let store = BrowserStore(projectID: "project-a")

        store.openAddressBar()
        let focusRequest = store.addressFocusRequest
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertTrue(store.consumeAddressFocusRequest())
        XCTAssertFalse(store.consumeAddressFocusRequest())

        store.collapse()
        XCTAssertEqual(store.presentation, .collapsed)

        store.expand()
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.addressFocusRequest, focusRequest)
        XCTAssertFalse(store.consumeAddressFocusRequest())

        store.close()
        XCTAssertEqual(store.presentation, .closed)
    }

    func testBrowserSessionsAreIsolatedByProject() {
        let store = BrowserStore(projectID: "project-a")

        store.openAddressBar()
        store.addressText = "https://project-a.example"
        store.collapse()

        store.selectProject("project-b")
        XCTAssertEqual(store.presentation, .closed)
        XCTAssertEqual(store.addressText, "")

        store.openAddressBar()
        store.addressText = "https://project-b.example"
        store.collapse()

        store.selectProject("project-a")
        XCTAssertEqual(store.presentation, .collapsed)
        XCTAssertEqual(store.addressText, "https://project-a.example")

        store.selectProject("project-b")
        XCTAssertEqual(store.presentation, .collapsed)
        XCTAssertEqual(store.addressText, "https://project-b.example")
    }

    func testSwitchingProjectsCollapsesExpandedBrowser() {
        let store = BrowserStore(projectID: "project-a")
        store.openAddressBar()

        store.selectProject("project-b")
        XCTAssertEqual(store.presentation, .closed)

        store.selectProject("project-a")
        XCTAssertEqual(store.presentation, .collapsed)
    }

    func testBrowserToolRegistryPublishesPlaywrightStyleTools() async {
        let browser = BrowserStore(projectID: "project-a")
        let registry = OpenClientDeviceToolRegistry(browserStore: browser)

        let toolIDs = await registry.listTools().map(\.id)

        XCTAssertTrue(toolIDs.contains("openclient_browser_navigate"))
        XCTAssertTrue(toolIDs.contains("openclient_browser_present"))
        XCTAssertTrue(toolIDs.contains("openclient_browser_clear_instruction"))
        XCTAssertTrue(toolIDs.contains("openclient_browser_snapshot"))
        XCTAssertTrue(toolIDs.contains("openclient_browser_click"))
        XCTAssertTrue(toolIDs.contains("openclient_browser_type"))
        XCTAssertTrue(toolIDs.contains("openclient_browser_history"))
    }

    func testBrowserAutomationSnapshotsClicksAndTypesUsingElementRefs() async throws {
        let store = BrowserStore(projectID: "project-a")
        store.openAddressBar()
        let webView = store.webView
        webView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><title>Automation Fixture</title></head>
              <body>
                <button aria-label="Continue" onclick="document.body.dataset.clicked='yes'">Continue</button>
                <input aria-label="Search" value="draft">
                <p>Visible fixture text</p>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://fixture.example")
        )
        for _ in 0 ..< 50 {
            if webView.url != nil, !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        store.close()

        let snapshot = try await store.automationSnapshot()
        let button = try XCTUnwrap(snapshot.elements.first { $0.role == "button" && $0.name == "Continue" })
        let input = try XCTUnwrap(snapshot.elements.first { $0.role == "textbox" && $0.name == "Search" })

        XCTAssertEqual(snapshot.page.title, "Automation Fixture")
        XCTAssertTrue(snapshot.visibleText.contains("Visible fixture text"))
        XCTAssertEqual(store.presentation, .closed)

        _ = try await store.automationClick(ref: button.ref)
        XCTAssertEqual(store.presentation, .closed)
        let clicked = try await javaScriptString("document.body.dataset.clicked", in: webView)
        XCTAssertEqual(clicked, "yes")

        _ = try await store.automationType(ref: input.ref, text: "OpenClient", clear: true, submit: false)
        XCTAssertEqual(store.presentation, .closed)
        let value = try await javaScriptString("document.querySelector('input').value", in: webView)
        XCTAssertEqual(value, "OpenClient")
    }

    func testBrowserPresentationToolExpandsWithInstruction() throws {
        let store = BrowserStore(projectID: "project-a")

        _ = try store.presentForAutomation(instruction: "Review the generated checkout details.")

        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.userInstruction, "Review the generated checkout details.")

        _ = try store.clearAutomationInstruction()
        XCTAssertNil(store.userInstruction)
    }

    func testBrowserAutomationActivityTracksCurrentToolStatus() throws {
        let store = BrowserStore(projectID: "project-a")

        let first = try store.beginAutomationActivity("Inspecting page")
        XCTAssertEqual(store.presentation, .collapsed)
        let second = try store.beginAutomationActivity("Entering text")
        XCTAssertEqual(store.automationStatus, "Entering text")

        store.endAutomationActivity(second)
        XCTAssertEqual(store.automationStatus, "Inspecting page")

        store.endAutomationActivity(first)
        XCTAssertNil(store.automationStatus)
    }

    private func javaScriptString(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let value = result as? String {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
