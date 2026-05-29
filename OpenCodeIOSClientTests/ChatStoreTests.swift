import XCTest
@testable import OpenClient

@MainActor
final class ChatStoreTests: XCTestCase {
    func testTranscriptWindowExpandsWhenLatestWindowHasNoDisplayableRows() {
        let sessionID = "ses_test"
        let visible = (0..<60).map { index in
            message(id: String(format: "msg_visible_%02d", index), role: "assistant", text: "Visible \(index)", sessionID: sessionID)
        }
        let hidden = (0..<50).map { index in
            emptyMessage(id: String(format: "msg_hidden_%02d", index), role: "assistant", sessionID: sessionID)
        }
        let messages = visible + hidden

        let window = OpenCodeChatTranscriptWindowing.window(
            from: messages,
            requestedCount: 50,
            batchSize: 50
        ) { messages in
            messages.contains { message in
                message.parts.contains { part in
                    part.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
            }
        }

        XCTAssertEqual(window.messages.count, 100)
        XCTAssertEqual(window.hiddenMessageCount, 10)
        XCTAssertTrue(window.messages.contains { $0.id == "msg_visible_10" })
        XCTAssertTrue(window.messages.contains { $0.id == "msg_hidden_49" })
    }

    func testTranscriptWindowExpandsToAllWhenNoMessagesAreDisplayable() {
        let messages = (0..<60).map { index in
            emptyMessage(id: String(format: "msg_hidden_%02d", index), role: "assistant", sessionID: "ses_test")
        }

        let window = OpenCodeChatTranscriptWindowing.window(
            from: messages,
            requestedCount: 50,
            batchSize: 50,
            hasDisplayableContent: { _ in false }
        )

        XCTAssertEqual(window.messages.count, 60)
        XCTAssertEqual(window.hiddenMessageCount, 0)
    }

    func testTranscriptWindowExpandsToIncludeParentForAssistantChildren() {
        let sessionID = "ses_test"
        let parent = message(id: "msg_parent", role: "user", text: "Start", sessionID: sessionID)
        let children = (0..<60).map { index in
            message(
                id: String(format: "msg_child_%02d", index),
                role: "assistant",
                text: "Child \(index)",
                sessionID: sessionID,
                parentID: parent.id
            )
        }
        let messages = [parent] + children

        let window = OpenCodeChatTranscriptWindowing.window(
            from: messages,
            requestedCount: 50,
            batchSize: 10
        ) { messages in
            messages.contains { message in
                message.parts.contains { part in
                    part.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
            }
        }

        XCTAssertEqual(window.messages.first?.id, parent.id)
        XCTAssertEqual(window.messages.count, 61)
        XCTAssertEqual(window.hiddenMessageCount, 0)
    }

    func testUpdateCachedMessagesForLiveActivityIfNeededAppliesOffscreenActiveSessionEvent() {
        let store = ChatStore(cachedMessagesBySessionID: [
            "ses_live": [message(id: "msg_assistant", role: "assistant", text: "Hello", sessionID: "ses_live")]
        ])
        let payload = OpenCodeEventEnvelope(
            type: "message.part.delta",
            properties: .init(
                sessionID: "ses_live",
                messageID: "msg_assistant",
                partID: "part_msg_assistant",
                field: "text",
                delta: " world"
            )
        )

        let updated = store.updateCachedMessagesForLiveActivityIfNeeded(
            payload: payload,
            sessionID: "ses_live",
            selectedSessionID: "ses_selected",
            activeLiveActivitySessionIDs: ["ses_live"],
            isLiveActivityMessageEvent: true
        )

        XCTAssertEqual(updated?.first?.parts.first?.text, "Hello world")
        XCTAssertEqual(store.cachedMessagesBySessionID["ses_live"]?.first?.parts.first?.text, "Hello world")
    }

    func testUpdateCachedMessagesForLiveActivityIfNeededIgnoresSelectedSessionEvent() {
        let original = message(id: "msg_assistant", role: "assistant", text: "Hello", sessionID: "ses_live")
        let store = ChatStore(cachedMessagesBySessionID: ["ses_live": [original]])
        let payload = OpenCodeEventEnvelope(
            type: "message.part.delta",
            properties: .init(
                sessionID: "ses_live",
                messageID: "msg_assistant",
                partID: "part_msg_assistant",
                field: "text",
                delta: " world"
            )
        )

        let updated = store.updateCachedMessagesForLiveActivityIfNeeded(
            payload: payload,
            sessionID: "ses_live",
            selectedSessionID: "ses_live",
            activeLiveActivitySessionIDs: ["ses_live"],
            isLiveActivityMessageEvent: true
        )

        XCTAssertNil(updated)
        XCTAssertEqual(store.cachedMessagesBySessionID["ses_live"]?.first?.parts.first?.text, "Hello")
    }

    func testUpdateCachedMessagesForLiveActivityIfNeededIgnoresInactiveLiveActivitySession() {
        let original = message(id: "msg_assistant", role: "assistant", text: "Hello", sessionID: "ses_live")
        let store = ChatStore(cachedMessagesBySessionID: ["ses_live": [original]])
        let payload = OpenCodeEventEnvelope(
            type: "message.part.delta",
            properties: .init(
                sessionID: "ses_live",
                messageID: "msg_assistant",
                partID: "part_msg_assistant",
                field: "text",
                delta: " world"
            )
        )

        let updated = store.updateCachedMessagesForLiveActivityIfNeeded(
            payload: payload,
            sessionID: "ses_live",
            selectedSessionID: "ses_selected",
            activeLiveActivitySessionIDs: [],
            isLiveActivityMessageEvent: true
        )

        XCTAssertNil(updated)
        XCTAssertEqual(store.cachedMessagesBySessionID["ses_live"]?.first?.parts.first?.text, "Hello")
    }

    private func message(id: String, role: String, text: String, sessionID: String, parentID: String? = nil) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: id, role: role, sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: parentID),
            parts: [
                OpenCodePart(id: "part_\(id)", messageID: id, sessionID: sessionID, type: "text", mime: nil, filename: nil, url: nil, reason: nil, tool: nil, callID: nil, state: nil, text: text)
            ]
        )
    }

    private func emptyMessage(id: String, role: String, sessionID: String) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: id, role: role, sessionID: sessionID, time: nil, agent: nil, model: nil),
            parts: []
        )
    }
}
