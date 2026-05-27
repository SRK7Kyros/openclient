import Foundation
import Darwin

struct CaptureConfiguration {
    var baseURL: URL
    var eventPath: String
    var username: String
    var password: String
    var logURL: URL
    var listenHost: String
    var listenPort: UInt16

    var eventURL: URL {
        if let explicit = URL(string: eventPath), explicit.scheme != nil {
            return explicit
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = eventPath.hasPrefix("/") ? eventPath : "/\(eventPath)"
        return components.url ?? baseURL.appendingPathComponent(eventPath)
    }

    static func parse(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CaptureConfiguration {
        var baseURL = environment["OPENCODE_BASE_URL"] ?? "http://127.0.0.1:4096"
        var eventPath = environment["OPENCODE_EVENT_PATH"] ?? "/global/event"
        var username = environment["OPENCODE_USERNAME"] ?? "opencode"
        var password = environment["OPENCODE_PASSWORD"] ?? ""
        var logPath = environment["OPENCODE_EVENT_CAPTURE_LOG"] ?? "tmp/opencode-event-capture.log"
        var listen = environment["OPENCODE_EVENT_CAPTURE_LISTEN"] ?? "127.0.0.1:9797"

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "--base-url":
                baseURL = try Self.nextValue(arguments, index: &index, for: argument)
            case "--event-path":
                eventPath = try Self.nextValue(arguments, index: &index, for: argument)
            case "--username":
                username = try Self.nextValue(arguments, index: &index, for: argument)
            case "--password":
                password = try Self.nextValue(arguments, index: &index, for: argument)
            case "--log":
                logPath = try Self.nextValue(arguments, index: &index, for: argument)
            case "--listen":
                listen = try Self.nextValue(arguments, index: &index, for: argument)
            case "--help", "-h":
                throw CaptureError.help
            default:
                throw CaptureError.invalidArgument(argument)
            }
        }

        guard let parsedBaseURL = URL(string: baseURL), parsedBaseURL.scheme != nil else {
            throw CaptureError.invalidBaseURL(baseURL)
        }

        let listenParts = listen.split(separator: ":", maxSplits: 1).map(String.init)
        guard listenParts.count == 2, let port = UInt16(listenParts[1]) else {
            throw CaptureError.invalidListenAddress(listen)
        }

        return CaptureConfiguration(
            baseURL: parsedBaseURL,
            eventPath: eventPath,
            username: username,
            password: password,
            logURL: URL(fileURLWithPath: logPath),
            listenHost: listenParts[0],
            listenPort: port
        )
    }

    private static func nextValue(_ arguments: [String], index: inout Int, for argument: String) throws -> String {
        guard index < arguments.count, !arguments[index].isEmpty else {
            throw CaptureError.missingValue(argument)
        }
        let value = arguments[index]
        index += 1
        return value
    }
}

enum CaptureError: Error, CustomStringConvertible {
    case help
    case invalidArgument(String)
    case missingValue(String)
    case invalidBaseURL(String)
    case invalidListenAddress(String)

    var description: String {
        switch self {
        case .help:
            return Self.usage
        case let .invalidArgument(argument):
            return "Invalid argument: \(argument)\n\n\(Self.usage)"
        case let .missingValue(argument):
            return "Missing value for \(argument)\n\n\(Self.usage)"
        case let .invalidBaseURL(value):
            return "Invalid --base-url: \(value)"
        case let .invalidListenAddress(value):
            return "Invalid --listen address: \(value). Expected host:port."
        }
    }

    static let usage = """
    Usage:
      swift scripts/opencode_event_capture.swift [options]

    Options:
      --base-url URL      OpenCode server base URL. Default: OPENCODE_BASE_URL or http://127.0.0.1:4096
      --event-path PATH   Event endpoint path or full URL. Default: OPENCODE_EVENT_PATH or /global/event
      --username USER     Basic auth username. Default: OPENCODE_USERNAME or opencode
      --password PASS     Basic auth password. Prefer OPENCODE_PASSWORD instead of this flag.
      --log PATH          Capture log path. Default: OPENCODE_EVENT_CAPTURE_LOG or tmp/opencode-event-capture.log
      --listen HOST:PORT  Local HTTP status server. Default: OPENCODE_EVENT_CAPTURE_LISTEN or 127.0.0.1:9797
    """
}

struct CaptureSnapshot: Sendable {
    var status: String
    var startedAt: Date
    var lineCount: Int
    var eventCount: Int
    var latestEventSummary: String
    var logPath: String
    var eventURL: String
}

actor EventLog {
    private let logURL: URL
    private let eventURL: URL
    private let handle: FileHandle
    private var lineCount = 0
    private var eventCount = 0
    private var status = "starting"
    private var latestEventSummary = "none"
    private let startedAt = Date()
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(logURL: URL, eventURL: URL) throws {
        self.logURL = logURL
        self.eventURL = eventURL
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: logURL)
    }

    deinit {
        try? handle.close()
    }

    func setStatus(_ nextStatus: String) {
        status = nextStatus
        appendLine("STATUS \(nextStatus)")
    }

    func appendRawLine(_ line: String) {
        appendLine("RAW \(line)")
    }

    func recordEvent(data: String) {
        eventCount += 1
        let summary = Self.summarizeEvent(data)
        latestEventSummary = summary
        appendLine("EVENT \(summary)")
        appendLine("JSON \(data)")
    }

    func snapshot() -> CaptureSnapshot {
        CaptureSnapshot(
            status: status,
            startedAt: startedAt,
            lineCount: lineCount,
            eventCount: eventCount,
            latestEventSummary: latestEventSummary,
            logPath: logURL.path,
            eventURL: eventURL.absoluteString
        )
    }

    func logContents(tail lineLimit: Int? = nil) -> String {
        let contents = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        guard let lineLimit, lineLimit > 0 else { return contents }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }

    private func appendLine(_ line: String) {
        lineCount += 1
        let timestamp = formatter.string(from: Date())
        if let data = "\(timestamp) \(line)\n".data(using: .utf8) {
            handle.write(data)
            try? handle.synchronize()
        }
    }

    private static func summarizeEvent(_ data: String) -> String {
        guard let jsonData = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return "unparseable bytes=\(data.utf8.count)"
        }

        let directory = object["directory"] as? String
        let rootType = object["type"] as? String
        let payload = object["payload"] as? [String: Any]
        let payloadType = payload?["type"] as? String
        let syncEvent = payload?["syncEvent"] as? [String: Any]
        let syncType = syncEvent?["type"] as? String
        let properties = (payload?["properties"] as? [String: Any])
            ?? (object["properties"] as? [String: Any])
            ?? (syncEvent?["data"] as? [String: Any])

        let type = syncType ?? payloadType ?? rootType ?? "unknown"
        let sessionID = (properties?["sessionID"] as? String) ?? (syncEvent?["aggregateID"] as? String)
        let info = properties?["info"] as? [String: Any]
        let infoID = info?["id"] as? String
        let title = info?["title"] as? String
        let messageID = (properties?["messageID"] as? String) ?? (info?["id"] as? String)
        let partID = properties?["partID"] as? String
        let part = properties?["part"] as? [String: Any]
        let nestedPartID = part?["id"] as? String
        let delta = properties?["delta"] as? String

        var fields = ["type=\(type)"]
        if let directory { fields.append("dir=\(directory)") }
        if let sessionID { fields.append("session=\(sessionID)") }
        if let infoID { fields.append("info=\(infoID)") }
        if let messageID { fields.append("message=\(messageID)") }
        if let partID = partID ?? nestedPartID { fields.append("part=\(partID)") }
        if let title { fields.append("title=\(Self.abbreviate(title))") }
        if let delta { fields.append("delta=\(Self.abbreviate(delta))") }
        return fields.joined(separator: " ")
    }

    private static func abbreviate(_ value: String, limit: Int = 80) -> String {
        let cleaned = value.replacingOccurrences(of: "\n", with: "\\n")
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit - 1)) + "..."
    }
}

final class SSEDataParser {
    private var dataLines: [String] = []

    func process(line: String) -> [String] {
        if line.isEmpty {
            return flush()
        }

        if line.hasPrefix("data:") {
            var value = String(line.dropFirst("data:".count))
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }

        return []
    }

    func flush() -> [String] {
        guard !dataLines.isEmpty else { return [] }
        let data = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true)
        return [data]
    }
}

final class EventCaptureClient {
    private let configuration: CaptureConfiguration
    private let log: EventLog

    init(configuration: CaptureConfiguration, log: EventLog) {
        self.configuration = configuration
        self.log = log
    }

    func run() async {
        while !Task.isCancelled {
            await connectOnce()
            if !Task.isCancelled {
                await log.setStatus("stream reconnecting in 1s")
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func connectOnce() async {
        await log.setStatus("stream connecting \(configuration.eventURL.absoluteString)")
        var request = URLRequest(url: configuration.eventURL)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if !configuration.username.isEmpty {
            let credentials = "\(configuration.username):\(configuration.password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = TimeInterval.infinity

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = TimeInterval.infinity
        sessionConfiguration.timeoutIntervalForResource = TimeInterval.infinity
        sessionConfiguration.waitsForConnectivity = true
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                await log.setStatus("stream invalid response")
                return
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                await log.setStatus("stream http \(http.statusCode)")
                return
            }

            await log.setStatus("stream open")
            let parser = SSEDataParser()
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                await log.appendRawLine(line)
                for data in parser.process(line: line) {
                    await log.recordEvent(data: data)
                }
            }
            for data in parser.flush() {
                await log.recordEvent(data: data)
            }
            await log.setStatus("stream ended")
        } catch {
            await log.setStatus("stream error \(error.localizedDescription)")
        }
    }
}

final class TinyHTTPServer {
    private let host: String
    private let port: UInt16
    private let log: EventLog
    private var serverSocket: Int32 = -1

    init(host: String, port: UInt16, log: EventLog) {
        self.host = host
        self.port = port
        self.log = log
    }

    func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw CaptureError.invalidListenAddress("\(host):\(port)")
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(serverSocket, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE) }
        guard listen(serverSocket, 16) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        Task.detached(priority: .background) { [weak self] in
            await self?.acceptLoop()
        }
    }

    private func acceptLoop() async {
        while serverSocket >= 0 {
            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = Darwin.accept(serverSocket, &address, &length)
            guard client >= 0 else { continue }
            Task.detached(priority: .background) { [weak self] in
                await self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) async {
        defer { close(client) }
        let request = readRequest(client: client)
        let target = request.firstLineTarget ?? "/"
        let response = await response(for: target)
        writeAll(response, to: client)
    }

    private func response(for target: String) async -> Data {
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        let query = target.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init)

        switch path {
        case "/", "/help":
            return httpResponse(status: "200 OK", contentType: "text/plain; charset=utf-8", body: """
            OpenCode event capture server

            GET /health      JSON status
            GET /log         Full capture log
            GET /log?tail=N  Last N log lines
            GET /help        This help text
            """)
        case "/health":
            let snapshot = await log.snapshot()
            let bodyObject: [String: Any] = [
                "status": snapshot.status,
                "startedAt": ISO8601DateFormatter().string(from: snapshot.startedAt),
                "lineCount": snapshot.lineCount,
                "eventCount": snapshot.eventCount,
                "latestEventSummary": snapshot.latestEventSummary,
                "logPath": snapshot.logPath,
                "eventURL": snapshot.eventURL,
            ]
            let body = (try? JSONSerialization.data(withJSONObject: bodyObject, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
            return httpResponse(status: "200 OK", contentType: "application/json; charset=utf-8", bodyData: body)
        case "/log":
            let tail = Self.tailLineLimit(from: query)
            let contents = await log.logContents(tail: tail)
            return httpResponse(status: "200 OK", contentType: "text/plain; charset=utf-8", body: contents)
        default:
            return httpResponse(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: "not found\n")
        }
    }

    private static func tailLineLimit(from query: String?) -> Int? {
        guard let query else { return nil }
        for item in query.split(separator: "&") {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == "tail" {
                return Int(parts[1])
            }
        }
        return nil
    }

    private func readRequest(client: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil && data.count < 16_384 {
            let count = Darwin.read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func httpResponse(status: String, contentType: String, body: String) -> Data {
        httpResponse(status: status, contentType: contentType, bodyData: Data(body.utf8))
    }

    private func httpResponse(status: String, contentType: String, bodyData: Data) -> Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status)\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(bodyData.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(bodyData)
        return response
    }

    private func writeAll(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.write(client, baseAddress.advanced(by: sent), data.count - sent)
                guard count > 0 else { break }
                sent += count
            }
        }
    }
}

private extension String {
    var firstLineTarget: String? {
        guard let firstLine = split(separator: "\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }
}

do {
    let configuration = try CaptureConfiguration.parse()
    let log = try EventLog(logURL: configuration.logURL, eventURL: configuration.eventURL)
    let server = TinyHTTPServer(host: configuration.listenHost, port: configuration.listenPort, log: log)
    try server.start()

    print("OpenCode event capture")
    print("event: \(configuration.eventURL.absoluteString)")
    print("log:   \(configuration.logURL.path)")
    print("http:  http://\(configuration.listenHost):\(configuration.listenPort)/health")
    print("stop:  Ctrl-C")

    await log.setStatus("capture starting")
    await EventCaptureClient(configuration: configuration, log: log).run()
} catch CaptureError.help {
    print(CaptureError.usage)
} catch let error as CaptureError {
    fputs("\(error.description)\n", stderr)
    exit(2)
} catch {
    fputs("Capture failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
