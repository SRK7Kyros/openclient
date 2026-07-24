import XCTest
@testable import OpenClient

@MainActor
final class ChatStoreTests: XCTestCase {
    func testInitialTranscriptRequestContainsLatestThreeUserRounds() {
        let sessionID = "ses_test"
        let messages = [
            OpenCodeMessage(id: "system", role: "system", sessionID: sessionID, time: nil, agent: nil, model: nil),
            OpenCodeMessage(id: "u0", role: "user", sessionID: sessionID, time: nil, agent: nil, model: nil),
            OpenCodeMessage(id: "a0", role: "assistant", sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: "u0"),
            OpenCodeMessage(id: "u1", role: "user", sessionID: sessionID, time: nil, agent: nil, model: nil),
            OpenCodeMessage(id: "a1", role: "assistant", sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: "u1"),
            OpenCodeMessage(id: "u2", role: "user", sessionID: sessionID, time: nil, agent: nil, model: nil),
            OpenCodeMessage(id: "a2a", role: "assistant", sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: "u2"),
            OpenCodeMessage(id: "a2b", role: "assistant", sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: "u2"),
            OpenCodeMessage(id: "u3", role: "user", sessionID: sessionID, time: nil, agent: nil, model: nil),
            OpenCodeMessage(id: "a3", role: "assistant", sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: "u3"),
            OpenCodeMessage(id: "u4", role: "user", sessionID: sessionID, time: nil, agent: nil, model: nil),
            OpenCodeMessage(id: "a4", role: "assistant", sessionID: sessionID, time: nil, agent: nil, model: nil, parentID: "u4"),
        ]

        let count = OpenCodeChatTranscriptWindowing.messageCountIncludingLatestUserRounds(
            3,
            fallbackMessageCount: 3,
            in: messages
        )

        XCTAssertEqual(count, 7)
        XCTAssertEqual(Array(messages.suffix(count)).map(\.id), ["u2", "a2a", "a2b", "u3", "a3", "u4", "a4"])
    }

    func testInitialTranscriptRequestFallsBackToThreeMessagesWithoutUserRounds() {
        let messages = (0..<20).map {
            OpenCodeMessage(id: "a\($0)", role: "assistant", sessionID: "ses_test", time: nil, agent: nil, model: nil)
        }

        XCTAssertEqual(
            OpenCodeChatTranscriptWindowing.messageCountIncludingLatestUserRounds(
                3,
                fallbackMessageCount: 3,
                in: messages
            ),
            3
        )
    }

    func testActivityBudgetKeepsProtectedContentAndNewestSettledActivity() {
        let projection = MessageBubbleActivityBudget.project(
            protectedEntries: Array(repeating: false, count: 20) + [true],
            limit: 12
        )

        XCTAssertEqual(projection.hiddenCount, 8)
        XCTAssertEqual(projection.firstHiddenIndex, 0)
        XCTAssertEqual(projection.retainedIndices, Set(8...20))
    }

    func testActivityBudgetDoesNotSpendLimitOnProtectedEntries() {
        var protectedEntries = Array(repeating: false, count: 20)
        protectedEntries[2] = true

        let projection = MessageBubbleActivityBudget.project(
            protectedEntries: protectedEntries,
            limit: 3
        )

        XCTAssertEqual(projection.hiddenCount, 16)
        XCTAssertTrue(projection.retainedIndices.contains(2))
        XCTAssertTrue(projection.retainedIndices.isSuperset(of: [17, 18, 19]))
    }

    func testUserPartPolicyDisplaysOnlyFirstNonSyntheticTextPart() throws {
        let original = OpenCodePart(id: "part_original", messageID: "msg_1", sessionID: "ses_1", type: "text", mime: nil, filename: nil, url: nil, reason: nil, tool: nil, callID: nil, state: nil, text: "@general inspect Downloads")
        let agent = OpenCodePart(id: "part_agent", messageID: "msg_1", sessionID: "ses_1", type: "agent", mime: nil, filename: nil, name: "general", url: nil, reason: nil, tool: nil, callID: nil, state: nil, text: nil)
        let synthetic = try JSONDecoder().decode(OpenCodePart.self, from: Data(#"{"id":"part_synthetic","messageID":"msg_1","sessionID":"ses_1","type":"text","text":"Use the above message and context to generate a prompt","synthetic":true}"#.utf8))
        let parts = [original, agent, synthetic]

        XCTAssertTrue(MessageBubbleUserPartPolicy.shouldDisplay(original, at: 0, in: parts))
        XCTAssertFalse(MessageBubbleUserPartPolicy.shouldDisplay(agent, at: 1, in: parts))
        XCTAssertFalse(MessageBubbleUserPartPolicy.shouldDisplay(synthetic, at: 2, in: parts))
        XCTAssertEqual(synthetic.synthetic, true)
    }

    func testTranscriptWindowLoadsOnlyRequestedSuffixForLongSession() {
        let messages = (0..<1_500).map { index in
            message(
                id: String(format: "msg_%04d", index),
                role: "assistant",
                text: "Visible \(index)",
                sessionID: "ses_test"
            )
        }
        var requestedSuffixes: [Int] = []

        let window = OpenCodeChatTranscriptWindowing.window(
            totalCount: messages.count,
            requestedCount: 50,
            batchSize: 50,
            loadSuffix: { count in
                requestedSuffixes.append(count)
                return Array(messages.suffix(count))
            },
            containsMessageID: { id in messages.contains { $0.id == id } },
            hasDisplayableContent: { !$0.isEmpty }
        )

        XCTAssertEqual(requestedSuffixes, [50])
        XCTAssertEqual(window.messages.count, 50)
        XCTAssertEqual(window.messages.first?.id, "msg_1450")
        XCTAssertEqual(window.hiddenMessageCount, 1_450)
    }

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

    func testDirectorySnapshotUsesReducerAppliedOffscreenTranscript() {
        let sessionID = "ses_live"
        let session = OpenCodeSession(
            id: sessionID,
            title: "Live",
            workspaceID: nil,
            directory: "/tmp/live",
            projectID: "project",
            parentID: nil
        )
        let registry = DirectoryStoreRegistry()
        let store = registry.store(for: session.directory)
        store.sessions = [session]
        store.applyCanonicalMessages(
            [message(id: "msg_assistant", role: "assistant", text: "Hello", sessionID: sessionID)],
            forSessionID: sessionID
        )
        let coordinator = EventSyncCoordinator()
        let state = EventSyncCoordinator.DirectoryEventState(
            sessions: store.sessions,
            selectedSession: nil,
            sessionStatuses: [:],
            syncState: store.syncState,
            messages: [],
            todos: [],
            permissions: [],
            questions: []
        )

        let application = coordinator.applyDirectoryEvents(
            [.messagePartDelta(
                sessionID: sessionID,
                messageID: "msg_assistant",
                partID: "part_msg_assistant",
                field: "text",
                delta: " world"
            )],
            to: state
        )
        store.applyReducedEventState(application.state, scopedSessions: application.state.sessions)

        XCTAssertEqual(
            registry.snapshot(forSessionID: sessionID)?.messages.first?.parts.first?.text,
            "Hello world"
        )
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
