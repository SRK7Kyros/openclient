import XCTest
@testable import OpenClient

@MainActor
final class LiveActivityStoreTests: XCTestCase {
    func testRefreshTaskReplacementCancelsPreviousTask() {
        let store = LiveActivityStore()
        let firstTask = Task { }
        let secondTask = Task { }

        store.setRefreshTask(firstTask, for: "ses_1")
        store.setRefreshTask(secondTask, for: "ses_1")

        XCTAssertTrue(firstTask.isCancelled)
        XCTAssertFalse(secondTask.isCancelled)
        XCTAssertTrue(store.hasPendingRefresh(for: "ses_1"))
    }

    func testPreviewRefreshTaskReplacementCancelsPreviousTask() {
        let store = LiveActivityStore()
        let firstTask = Task { }
        let secondTask = Task { }

        store.setPreviewRefreshTask(firstTask, for: "ses_1")
        store.setPreviewRefreshTask(secondTask, for: "ses_1")

        XCTAssertTrue(firstTask.isCancelled)
        XCTAssertFalse(secondTask.isCancelled)
    }

#if canImport(ActivityKit) && os(iOS)
    func testLastStateCanBeStoredAndCleared() {
        let store = LiveActivityStore()
        let state = OpenCodeChatActivityAttributes.ContentState(
            status: "Working",
            latestSnippet: "Running tests",
            transcriptLines: [],
            updatedAt: Date(timeIntervalSince1970: 100),
            pendingInteractionKind: nil,
            interactionID: nil,
            interactionTitle: nil,
            interactionSummary: nil,
            questionOptionLabels: [],
            canReplyToQuestionInline: false
        )

        store.setLastState(state, for: "ses_1")
        XCTAssertEqual(store.lastState(for: "ses_1"), state)

        store.setLastState(nil, for: "ses_1")
        XCTAssertNil(store.lastState(for: "ses_1"))
    }
#endif
}
