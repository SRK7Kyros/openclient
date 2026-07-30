import Foundation

struct OpenClientLoadedImage: Equatable, @unchecked Sendable {
    let data: Data
    let platformImage: OpenClientPlatformImage
    let width: Int
    let height: Int

    static func == (lhs: OpenClientLoadedImage, rhs: OpenClientLoadedImage) -> Bool {
        lhs.data == rhs.data && lhs.width == rhs.width && lhs.height == rhs.height
    }
}

protocol OpenClientImageContentTransport: Sendable {
    func load(
        payload: OpenClientVisualImagePayload,
        endpoint: OpenClientBridgeEndpoint
    ) async throws -> OpenClientLoadedImage
}

actor OpenClientImageContentClient: OpenClientImageContentTransport {
    private let configuration: URLSessionConfiguration

    init(sessionConfiguration: URLSessionConfiguration? = nil) {
        if let sessionConfiguration,
           let copied = sessionConfiguration.copy() as? URLSessionConfiguration {
            configuration = copied
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 30
            self.configuration = configuration
        }
    }

    func load(
        payload: OpenClientVisualImagePayload,
        endpoint: OpenClientBridgeEndpoint
    ) async throws -> OpenClientLoadedImage {
        let payload = try payload.validated()
        let url = try Self.url(path: payload.contentPath, resourceID: payload.resourceID, endpoint: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(payload.file.mimeType, forHTTPHeaderField: "Accept")

        let loader = OpenClientBoundedImageRequest(
            configuration: configuration,
            expectedContentType: payload.file.mimeType,
            expectedContentLength: payload.file.sizeBytes,
            maximumBytes: OpenClientVisualImageContract.maximumFileBytes
        )
        let data = try await loader.load(request)
        guard !data.isEmpty else {
            throw OpenClientImageContentError.emptyResponse
        }
        guard Int64(data.count) == payload.file.sizeBytes else {
            throw OpenClientImageContentError.invalidContentLength(
                expected: payload.file.sizeBytes,
                actual: Int64(data.count)
            )
        }
        guard let decoded = OpenClientPlatformImageDecoder.decode(data) else {
            throw OpenClientImageContentError.invalidImage
        }
        guard decoded.width == payload.width, decoded.height == payload.height else {
            throw OpenClientImageContentError.dimensionMismatch(
                expectedWidth: payload.width,
                expectedHeight: payload.height,
                actualWidth: decoded.width,
                actualHeight: decoded.height
            )
        }
        return OpenClientLoadedImage(
            data: data,
            platformImage: decoded.image,
            width: decoded.width,
            height: decoded.height
        )
    }

    static func url(
        path: String,
        resourceID: String,
        endpoint: OpenClientBridgeEndpoint
    ) throws -> URL {
        guard path == "/openclient/v1/image/resources/\(resourceID)/content",
              !path.contains(".."),
              !path.contains("?"),
              !path.contains("#") else {
            throw OpenClientImageContentError.invalidPath
        }
        guard var components = URLComponents(url: endpoint.healthURL, resolvingAgainstBaseURL: false) else {
            throw OpenClientImageContentError.invalidEndpoint
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw OpenClientImageContentError.invalidEndpoint
        }
        return url
    }
}

enum OpenClientImageContentError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidPath
    case unavailable
    case invalidResponse
    case statusCode(Int)
    case invalidContentType(expected: String, actual: String?)
    case invalidContentLength(expected: Int64, actual: Int64)
    case emptyResponse
    case responseTooLarge
    case invalidImage
    case dimensionMismatch(expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The OpenClient plugin image endpoint is invalid."
        case .invalidPath:
            return "The OpenClient plugin image path is invalid."
        case .unavailable:
            return "Connect to the OpenClient plugin before viewing this image."
        case .invalidResponse:
            return "The OpenClient plugin returned an invalid image response."
        case .statusCode(let status):
            return "The image service returned HTTP \(status)."
        case .invalidContentType:
            return "The image service returned an unexpected content type."
        case .invalidContentLength:
            return "The image service returned an unexpected number of bytes."
        case .emptyResponse:
            return "The image service returned an empty image."
        case .responseTooLarge:
            return "The image exceeds the supported size limit."
        case .invalidImage:
            return "The image service returned data that cannot be displayed as an image."
        case .dimensionMismatch:
            return "The image dimensions do not match the persisted metadata."
        case .network(let message):
            return message
        }
    }
}

private final class OpenClientBoundedImageRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let expectedContentType: String
    private let expectedContentLength: Int64
    private let maximumBytes: Int64
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var wasCancelled = false

    init(
        configuration: URLSessionConfiguration,
        expectedContentType: String,
        expectedContentLength: Int64,
        maximumBytes: Int64
    ) {
        self.configuration = configuration.copy() as? URLSessionConfiguration ?? configuration
        self.expectedContentType = expectedContentType
        self.expectedContentLength = expectedContentLength
        self.maximumBytes = maximumBytes
    }

    func load(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if wasCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.session = session
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(OpenClientImageContentError.invalidResponse))
            return
        }
        guard response.statusCode == 200 else {
            completionHandler(.cancel)
            finish(.failure(OpenClientImageContentError.statusCode(response.statusCode)))
            return
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        guard contentType == expectedContentType else {
            completionHandler(.cancel)
            finish(.failure(OpenClientImageContentError.invalidContentType(
                expected: expectedContentType,
                actual: contentType
            )))
            return
        }
        if let value = response.value(forHTTPHeaderField: "Content-Length") {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let contentLength = Int64(trimmed), contentLength == expectedContentLength else {
                completionHandler(.cancel)
                finish(.failure(OpenClientImageContentError.invalidContentLength(
                    expected: expectedContentLength,
                    actual: Int64(trimmed) ?? -1
                )))
                return
            }
        }

        lock.lock()
        self.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        let nextCount = Int64(data.count) + Int64(chunk.count)
        let error: OpenClientImageContentError?
        if nextCount > maximumBytes {
            error = .responseTooLarge
        } else if nextCount > expectedContentLength {
            error = .invalidContentLength(expected: expectedContentLength, actual: nextCount)
        } else {
            data.append(chunk)
            error = nil
        }
        lock.unlock()

        if let error {
            dataTask.cancel()
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            lock.lock()
            let cancelled = wasCancelled
            lock.unlock()
            finish(.failure(cancelled ? CancellationError() : OpenClientImageContentError.network(error.localizedDescription)))
            return
        }

        lock.lock()
        let response = response
        let result = data
        lock.unlock()
        guard response != nil else {
            finish(.failure(OpenClientImageContentError.invalidResponse))
            return
        }
        finish(.success(result))
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        task = nil
        let session = session
        self.session = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
