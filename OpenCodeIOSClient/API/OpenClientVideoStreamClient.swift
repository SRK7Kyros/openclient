import Foundation

struct OpenClientVideoStream: Equatable, Sendable {
    let id: String
    let playlistURL: URL
    let stopPath: String
}

protocol OpenClientVideoStreamTransport: Sendable {
    func start(
        payload: OpenClientVisualVideoPayload,
        endpoint: OpenClientBridgeEndpoint
    ) async throws -> OpenClientVideoStream
    func stop(
        stream: OpenClientVideoStream,
        endpoint: OpenClientBridgeEndpoint
    ) async throws
}

actor OpenClientVideoStreamClient: OpenClientVideoStreamTransport {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    func start(
        payload: OpenClientVisualVideoPayload,
        endpoint: OpenClientBridgeEndpoint
    ) async throws -> OpenClientVideoStream {
        let payload = try payload.validated()
        let url = try Self.url(path: payload.startPath, endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data, expectedStatus: 200)
        let result = try JSONDecoder().decode(StartResponse.self, from: data)
        let streamStopPath = "/openclient/v1/video/streams/\(result.streamID)"
        guard result.streamID.count == 32,
              result.streamID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
              }),
              result.hlsPath == "/openclient/v1/video/streams/\(result.streamID)/playlist.m3u8",
              result.stopPath == streamStopPath else {
            throw OpenClientVideoStreamError.invalidResponse
        }
        return OpenClientVideoStream(
            id: result.streamID,
            playlistURL: try Self.url(path: result.hlsPath, endpoint: endpoint),
            stopPath: result.stopPath
        )
    }

    func stop(
        stream: OpenClientVideoStream,
        endpoint: OpenClientBridgeEndpoint
    ) async throws {
        let streamStopPath = "/openclient/v1/video/streams/\(stream.id)"
        guard stream.stopPath == streamStopPath else {
            throw OpenClientVideoStreamError.invalidResponse
        }
        let url = try Self.url(path: stream.stopPath, endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenClientVideoStreamError.invalidResponse
        }
        guard response.statusCode == 204 || response.statusCode == 404 else {
            throw OpenClientVideoStreamError.server(Self.errorMessage(data: data, status: response.statusCode))
        }
    }

    static func url(path: String, endpoint: OpenClientBridgeEndpoint) throws -> URL {
        guard path.hasPrefix("/openclient/v1/video/"),
              !path.contains(".."),
              !path.contains("?"),
              !path.contains("#") else {
            throw OpenClientVideoStreamError.invalidResponse
        }
        guard var components = URLComponents(url: endpoint.healthURL, resolvingAgainstBaseURL: false) else {
            throw OpenClientVideoStreamError.invalidEndpoint
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw OpenClientVideoStreamError.invalidEndpoint
        }
        return url
    }

    private static func validate(
        response: URLResponse,
        data: Data,
        expectedStatus: Int
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw OpenClientVideoStreamError.invalidResponse
        }
        guard response.statusCode == expectedStatus else {
            throw OpenClientVideoStreamError.server(errorMessage(data: data, status: response.statusCode))
        }
    }

    private static func errorMessage(data: Data, status: Int) -> String {
        if let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !response.error.isEmpty {
            return response.error
        }
        return String(localized: "The video service returned HTTP \(status).")
    }
}

enum OpenClientVideoStreamError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidResponse
    case unavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "The OpenClient plugin video endpoint is invalid.")
        case .invalidResponse:
            return String(localized: "The OpenClient plugin returned an invalid video response.")
        case .unavailable:
            return String(localized: "Connect to the OpenClient plugin before playing this video.")
        case .server(let message):
            return message
        }
    }
}

private struct StartResponse: Decodable {
    let streamID: String
    let hlsPath: String
    let stopPath: String
}

private struct ErrorResponse: Decodable {
    let error: String
}
