import XCTest
@testable import OpenClient

final class OpenCodeShortcutTests: XCTestCase {
    private let recentServerConfigsKey = "recentServerConfigs"
    private var previousRecentServerConfigs: Data?
    private var passwordIDsToClean: Set<String> = []

    override func setUp() {
        super.setUp()
        previousRecentServerConfigs = UserDefaults.standard.data(forKey: recentServerConfigsKey)
        UserDefaults.standard.removeObject(forKey: recentServerConfigsKey)
        ShortcutMockURLProtocol.requestHandler = nil
        passwordIDsToClean = []
    }

    override func tearDown() {
        if let previousRecentServerConfigs {
            UserDefaults.standard.set(previousRecentServerConfigs, forKey: recentServerConfigsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: recentServerConfigsKey)
        }
        for serverID in passwordIDsToClean {
            OpenCodeServerPasswordStore().deletePassword(for: serverID)
        }
        ShortcutMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testShortcutEntityIDRoundTripsConnectionIDsWithSeparators() throws {
        let connectionID = "http://127.0.0.1:4096|opencode"
        let id = OpenCodeShortcutEntityID.make(kind: "session", components: [connectionID, "proj|one", "ses/one"])

        XCTAssertEqual(
            OpenCodeShortcutEntityID.components(from: id, kind: "session"),
            [connectionID, "proj|one", "ses/one"]
        )
        XCTAssertNil(OpenCodeShortcutEntityID.components(from: id, kind: "project"))
    }

    func testShortcutModelsFetchFiltersDeprecatedAndMapsReasoning() async throws {
        let connection = try saveShortcutConnection()
        let service = OpenCodeShortcutService(session: makeMockSession(), usageGate: unlockedUsageGate())

        ShortcutMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/provider")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic b3BlbmNvZGU6cHc=")
            let data = Self.data("""
            {
              "all": [
                {
                  "id": "openai",
                  "name": "OpenAI",
                  "models": {
                    "gpt-5": {
                      "id": "gpt-5",
                      "providerID": "openai",
                      "name": "GPT-5",
                      "capabilities": { "reasoning": true },
                      "variants": { "balanced": true, "deep": true }
                    },
                    "old": {
                      "id": "old",
                      "providerID": "openai",
                      "name": "Old",
                      "capabilities": { "reasoning": false },
                      "status": "deprecated"
                    }
                  }
                },
                {
                  "id": "anthropic",
                  "name": "Anthropic",
                  "models": {
                    "claude": {
                      "id": "claude",
                      "providerID": "anthropic",
                      "name": "Claude",
                      "capabilities": { "reasoning": true },
                      "variants": { "think": true }
                    }
                  }
                }
              ],
              "connected": ["openai"],
              "default": {}
            }
            """)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let models = try await service.models(connection: connection)

        XCTAssertEqual(models.map(\.modelID), ["gpt-5"])
        XCTAssertEqual(models.first?.reasoningVariants, ["balanced", "deep"])
    }

    func testCreateSessionAndSendMessageUsesProjectModelAndReasoning() async throws {
        let connection = try saveShortcutConnection()
        let project = OpenCodeShortcutProjectEntity(
            id: OpenCodeShortcutEntityID.make(kind: "project", components: [connection.id, "proj_1"]),
            connectionID: connection.id,
            projectID: "proj_1",
            title: "Project",
            directory: "/tmp/project"
        )
        let model = OpenCodeShortcutModelEntity(
            id: OpenCodeShortcutEntityID.make(kind: "model", components: [connection.id, "openai", "gpt-5"]),
            connectionID: connection.id,
            providerID: "openai",
            providerName: "OpenAI",
            modelID: "gpt-5",
            modelName: "GPT-5",
            reasoningVariants: ["balanced"]
        )
        let service = OpenCodeShortcutService(session: makeMockSession(), usageGate: unlockedUsageGate())
        var requests: [URLRequest] = []

        ShortcutMockURLProtocol.requestHandler = { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/session"):
                XCTAssertEqual(request.url?.query, "directory=/tmp/project")
                let body = try XCTUnwrap(request.httpBodyData)
                XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["title": "Shortcut"])
                let data = Self.data("""
                {
                  "id": "ses_1",
                  "title": "Shortcut",
                  "workspaceID": null,
                  "directory": "/tmp/project",
                  "projectID": "proj_1",
                  "parentID": null
                }
                """)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            case ("POST", "/session/ses_1/prompt_async"):
                XCTAssertEqual(request.url?.query, "directory=/tmp/project")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-opencode-directory"), "/tmp/project")
                let body = try XCTUnwrap(request.httpBodyData)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["variant"] as? String, "balanced")
                XCTAssertEqual((json["model"] as? [String: String])?["providerID"], "openai")
                XCTAssertEqual((json["model"] as? [String: String])?["modelID"], "gpt-5")
                let parts = try XCTUnwrap(json["parts"] as? [[String: Any]])
                XCTAssertEqual(parts.first?["text"] as? String, "Hello from shortcuts")
                return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.absoluteString ?? "nil")")
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }

        let session = try await service.createSessionAndSendMessage(
            connection: connection,
            project: project,
            title: " Shortcut ",
            message: " Hello from shortcuts ",
            model: model,
            reasoning: "balanced"
        )

        XCTAssertEqual(session.sessionID, "ses_1")
        XCTAssertEqual(session.providerID, "openai")
        XCTAssertEqual(session.modelID, "gpt-5")
        XCTAssertEqual(session.reasoningVariant, "balanced")
        XCTAssertEqual(requests.map { $0.url?.path }, ["/session", "/session/ses_1/prompt_async"])
    }

    private func saveShortcutConnection() throws -> OpenCodeShortcutConnectionEntity {
        let saved = OpenCodeSavedServer(name: "Test", iconName: "server.rack", baseURL: "http://shortcut.test", username: "opencode")
        let data = try JSONEncoder().encode([saved])
        UserDefaults.standard.set(data, forKey: recentServerConfigsKey)
        OpenCodeServerPasswordStore().savePassword("pw", for: saved.recentServerID)
        passwordIDsToClean.insert(saved.recentServerID)
        return try XCTUnwrap(OpenCodeShortcutService().connections().first)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShortcutMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func unlockedUsageGate() -> OpenCodeShortcutUsageGate {
        OpenCodeShortcutUsageGate(isProUnlocked: { true })
    }

    private static func data(_ string: String) -> Data {
        string.data(using: .utf8)!
    }
}

private final class ShortcutMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var httpBodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
