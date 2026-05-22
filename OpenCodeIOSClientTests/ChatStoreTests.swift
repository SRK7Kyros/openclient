import XCTest
@testable import OpenClient

@MainActor
final class ChatStoreTests: XCTestCase {
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

    private func message(id: String, role: String, text: String, sessionID: String) -> OpenCodeMessageEnvelope {
        OpenCodeMessageEnvelope(
            info: OpenCodeMessage(id: id, role: role, sessionID: sessionID, time: nil, agent: nil, model: nil),
            parts: [
                OpenCodePart(id: "part_\(id)", messageID: id, sessionID: sessionID, type: "text", mime: nil, filename: nil, url: nil, reason: nil, tool: nil, callID: nil, state: nil, text: text)
            ]
        )
    }
}
