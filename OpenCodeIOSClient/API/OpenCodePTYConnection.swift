import Foundation

enum OpenCodePTYConnectionError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        String(localized: "The terminal is not connected.")
    }
}

actor OpenCodePTYConnection {
    private struct CursorMetadata: Decodable {
        let cursor: Int
    }

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?

    func run(
        request: URLRequest,
        initialCursor: Int,
        onEvent: @escaping @Sendable (OpenCodePTYSocketEvent) async -> Void
    ) async throws {
        disconnect()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 4 * 1_024 * 1_024
        self.session = session
        self.socket = socket
        var cursor = initialCursor

        socket.resume()
        await onEvent(.connected)

        defer {
            if self.socket === socket {
                self.socket = nil
                self.session = nil
            }
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        while !Task.isCancelled {
            let message = try await socket.receive()
            switch message {
            case let .string(text):
                cursor += text.utf16.count
                await onEvent(.output(text, cursor: cursor))
            case let .data(data):
                if let authoritativeCursor = Self.decodeCursorMetadata(data) {
                    cursor = authoritativeCursor
                    await onEvent(.cursor(authoritativeCursor))
                }
            @unknown default:
                continue
            }
        }

        throw CancellationError()
    }

    func send(_ bytes: [UInt8]) async throws {
        guard let socket else { throw OpenCodePTYConnectionError.notConnected }
        let text = String(decoding: bytes, as: UTF8.self)
        try await socket.send(.string(text))
    }

    func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    nonisolated static func decodeCursorMetadata(_ data: Data) -> Int? {
        guard data.first == 0 else { return nil }
        return try? JSONDecoder().decode(CursorMetadata.self, from: Data(data.dropFirst())).cursor
    }
}
