import Foundation

struct OpenCodeManagedEvent: Sendable {
    let directory: String
    let envelope: OpenCodeEventEnvelope
    let typed: OpenCodeTypedEvent
}

enum OpenCodeManagedEventDecodeResult: Sendable {
    case event(OpenCodeManagedEvent)
    case dropped(String)
}

actor OpenCodeManagedEventBatcher {
    private static let maxEventsPerFlush = 24

    private struct QueuedEvent: Sendable {
        let directory: String
        let event: OpenCodeManagedEvent
    }

    private let onEvent: @Sendable (OpenCodeManagedEvent) async -> Void
    private var queue: [QueuedEvent] = []
    private var coalescedIndexes: [String: Int] = [:]
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false

    init(onEvent: @escaping @Sendable (OpenCodeManagedEvent) async -> Void) {
        self.onEvent = onEvent
    }

    func enqueue(_ event: OpenCodeManagedEvent) {
        let directory = event.directory
        if let key = coalescingKey(directory: directory, event: event),
           let index = coalescedIndexes[key] {
            queue[index] = QueuedEvent(directory: directory, event: event)
            scheduleFlush()
            return
        }

        if let key = coalescingKey(directory: directory, event: event) {
            coalescedIndexes[key] = queue.count
        }
        queue.append(QueuedEvent(directory: directory, event: event))
        scheduleFlush()
    }

    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        flushTask?.cancel()
        flushTask = nil

        while !queue.isEmpty {
            let count = min(queue.count, Self.maxEventsPerFlush)
            let events = Array(queue.prefix(count))
            queue.removeFirst(count)
            rebuildCoalescedIndexes()

            for item in events {
                await onEvent(item.event)
            }
        }
    }

    private func scheduleFlush() {
        guard !isFlushing else { return }
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            await self?.flush()
        }
    }

    private func coalescingKey(directory: String, event: OpenCodeManagedEvent) -> String? {
        switch event.envelope.type {
        case "session.status":
            guard let sessionID = event.envelope.properties.sessionID else { return nil }
            return "session.status:\(directory):\(sessionID)"
        case "lsp.updated":
            return "lsp.updated:\(directory)"
        default:
            return nil
        }
    }

    private func rebuildCoalescedIndexes() {
        coalescedIndexes = [:]
        for (index, item) in queue.enumerated() {
            guard let key = coalescingKey(directory: item.directory, event: item.event) else { continue }
            coalescedIndexes[key] = index
        }
    }
}

private actor OpenCodeStreamHeartbeat {
    private var lastEventAt = Date.now

    func markEvent() {
        lastEventAt = .now
    }

    func isTimedOut(timeout: TimeInterval) -> Bool {
        Date.now.timeIntervalSince(lastEventAt) >= timeout
    }
}

@MainActor
final class OpenCodeEventManager {
    private static let heartbeatTimeoutSeconds: TimeInterval = 15
    private var task: Task<Void, Never>?
    private var managedEventObserver: (@Sendable (OpenCodeManagedEvent) async -> Void)?

    func setManagedEventObserver(
        _ observer: (@Sendable (OpenCodeManagedEvent) async -> Void)?
    ) {
        managedEventObserver = observer
    }

    nonisolated static func decodeManagedEvent(from rawData: String) -> OpenCodeManagedEventDecodeResult {
        guard let data = rawData.data(using: .utf8) else {
            return .dropped("drop event: non-utf8 payload")
        }

        guard let global = try? JSONDecoder().decode(OpenCodeGlobalEventEnvelope.self, from: data) else {
            if let recovered = recoverPartUpdatedEvent(from: rawData) {
                return .event(recovered)
            }
            return .dropped("drop event: invalid global envelope \(String(rawData.prefix(160)))")
        }

        guard let envelope = global.event else {
            return .dropped("drop event: missing inner envelope dir=\(global.directory ?? "global")")
        }

        guard let typed = OpenCodeTypedEvent(envelope: envelope) else {
            if envelope.type == "message.part.updated",
               let recovered = recoverPartUpdatedEvent(from: rawData) {
                return .event(recovered)
            }
            return .dropped("drop event: untyped \(envelope.type) dir=\(global.directory ?? "global")")
        }

        return .event(
            OpenCodeManagedEvent(
                directory: global.directory ?? "global",
                envelope: envelope,
                typed: typed
            )
        )
    }

    func start(
        client: OpenCodeAPIClient,
        onStatus: @escaping @Sendable (String) async -> Void,
        onRawLine: (@Sendable (String) async -> Void)? = nil,
        onDroppedEvent: (@Sendable (String) async -> Void)? = nil,
        onEvent: @escaping @Sendable (OpenCodeManagedEvent) async -> Void
    ) {
        stop()
        let managedEventObserver = self.managedEventObserver
        task = Task.detached {
            await Self.runStreamLoop(
                client: client,
                onStatus: onStatus,
                onRawLine: onRawLine,
                onDroppedEvent: onDroppedEvent,
                onEvent: { managed in
                    await onEvent(managed)
                    await managedEventObserver?(managed)
                }
            )
        }
    }

    nonisolated private static func recoverPartUpdatedEvent(from rawData: String) -> OpenCodeManagedEvent? {
        guard let data = rawData.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let eventObject = root["payload"] as? [String: Any] ?? root
        guard eventObject["type"] as? String == "message.part.updated",
              let properties = eventObject["properties"] as? [String: Any],
              let part = recoverPartUpdatedPart(from: properties) else {
            return nil
        }

        let sessionID = stringValue(for: "sessionID", in: properties) ?? part.sessionID
        let messageID = stringValue(for: "messageID", in: properties) ?? part.messageID
        let partID = stringValue(for: "partID", in: properties) ?? part.id
        let eventProperties = OpenCodeEventProperties(
            sessionID: sessionID,
            part: part,
            text: stringValue(for: "text", in: properties),
            mime: stringValue(for: "mime", in: properties),
            filename: stringValue(for: "filename", in: properties),
            url: stringValue(for: "url", in: properties),
            reason: stringValue(for: "reason", in: properties),
            messageID: messageID,
            partID: partID,
            permissionType: stringValue(for: "type", in: properties),
            callID: stringValue(for: "callID", in: properties)
        )
        let envelope = OpenCodeEventEnvelope(type: "message.part.updated", properties: eventProperties)

        return OpenCodeManagedEvent(
            directory: root["directory"] as? String ?? "global",
            envelope: envelope,
            typed: .messagePartUpdated(part)
        )
    }

    nonisolated private static func recoverPartUpdatedPart(from properties: [String: Any]) -> OpenCodePart? {
        let nested = properties["part"] as? [String: Any]
        func value(_ key: String) -> Any? {
            nested?[key] ?? properties[key]
        }

        let toolName: String? = {
            if let value = value("tool") as? String { return value }
            if let object = value("tool") as? [String: Any] { return stringValue(for: "name", in: object) }
            return nil
        }()
        let type = stringValue(for: "type", in: nested ?? [:])
            ?? stringValue(for: "type", in: properties)
            ?? (toolName != nil ? "tool" : (stringValue(for: "text", in: nested ?? properties) != nil ? "text" : nil))
        guard let type else { return nil }

        let messageID = stringValue(for: "messageID", in: nested ?? [:]) ?? stringValue(for: "messageID", in: properties)
        let partID = stringValue(for: "id", in: nested ?? [:]) ?? stringValue(for: "partID", in: properties) ?? stringValue(for: "id", in: properties)
        let sessionID = stringValue(for: "sessionID", in: nested ?? [:]) ?? stringValue(for: "sessionID", in: properties)

        return OpenCodePart(
            id: partID,
            messageID: messageID,
            sessionID: sessionID,
            type: type,
            mime: stringValue(for: "mime", in: nested ?? [:]) ?? stringValue(for: "mime", in: properties),
            filename: stringValue(for: "filename", in: nested ?? [:]) ?? stringValue(for: "filename", in: properties),
            name: stringValue(for: "name", in: nested ?? [:]) ?? stringValue(for: "name", in: properties),
            url: stringValue(for: "url", in: nested ?? [:]) ?? stringValue(for: "url", in: properties),
            source: nil,
            reason: stringValue(for: "reason", in: nested ?? [:]) ?? stringValue(for: "reason", in: properties),
            tool: toolName,
            callID: stringValue(for: "callID", in: nested ?? [:]) ?? stringValue(for: "callID", in: properties),
            state: nil,
            text: stringValue(for: "text", in: nested ?? [:]) ?? stringValue(for: "text", in: properties)
        )
        .applyingEventFallbacks(sessionID: sessionID, messageID: messageID, partID: partID)
    }

    nonisolated private static func stringValue(for key: String, in dictionary: [String: Any]) -> String? {
        dictionary[key] as? String
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    nonisolated private static func runStreamLoop(
        client: OpenCodeAPIClient,
        onStatus: @escaping @Sendable (String) async -> Void,
        onRawLine: (@Sendable (String) async -> Void)? = nil,
        onDroppedEvent: (@Sendable (String) async -> Void)? = nil,
        onEvent: @escaping @Sendable (OpenCodeManagedEvent) async -> Void
    ) async {
        var reconnectAttempt = 0
        let batcher = OpenCodeManagedEventBatcher(onEvent: onEvent)

        while !Task.isCancelled {
            guard let url = client.globalEventURL() else {
                await onStatus("stream invalid url")
                return
            }

            let startedAt = Date.now
            let heartbeat = OpenCodeStreamHeartbeat()
            let streamTask = Task {
                await OpenCodeEventStream.consume(
                    client: client,
                    url: url,
                    onStatus: onStatus,
                    onRawLine: onRawLine,
                    onEvent: { event in
                        await heartbeat.markEvent()
                        switch Self.decodeManagedEvent(from: event.data) {
                        case let .event(managed):
                            await batcher.enqueue(managed)
                        case let .dropped(message):
                            await onDroppedEvent?(message)
                        }
                    }
                )
            }
            let heartbeatTask = Task { [streamTask] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Int(Self.heartbeatTimeoutSeconds)))
                    guard !Task.isCancelled else { return }
                    guard await heartbeat.isTimedOut(timeout: Self.heartbeatTimeoutSeconds) else { continue }
                    await onStatus("stream heartbeat timeout")
                    streamTask.cancel()
                    return
                }
            }

            await withTaskCancellationHandler {
                await streamTask.value
            } onCancel: {
                streamTask.cancel()
                heartbeatTask.cancel()
            }
            heartbeatTask.cancel()

            await batcher.flush()

            if Task.isCancelled {
                return
            }

            if Date.now.timeIntervalSince(startedAt) > 10 {
                reconnectAttempt = 0
            }

            let delaySeconds = min(8.0, 0.25 * pow(2.0, Double(reconnectAttempt))) + Double.random(in: 0 ... 0.2)
            reconnectAttempt = min(reconnectAttempt + 1, 6)
            await onStatus("stream reconnecting")
            try? await Task.sleep(for: .milliseconds(Int(delaySeconds * 1_000)))
        }
    }
}
