import Foundation

let openClientBridgeProtocolVersion = 1

enum OpenClientJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: OpenClientJSONValue])
    case array([OpenClientJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: OpenClientJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([OpenClientJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var objectValue: [String: OpenClientJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }
}

struct OpenClientDeviceToolDescriptor: Codable, Equatable, Sendable {
    let id: String
    let description: String
    let inputSchema: [String: OpenClientJSONValue]

    var jsonValue: OpenClientJSONValue {
        .object([
            "id": .string(id),
            "description": .string(description),
            "inputSchema": .object(inputSchema),
        ])
    }
}

struct OpenClientRemoteToolContext: Equatable, Sendable {
    let sessionID: String
    let messageID: String
    let agent: String
    let directory: String
    let worktree: String

    init(jsonValue: OpenClientJSONValue) throws {
        guard let object = jsonValue.objectValue else {
            throw OpenClientBridgeProtocolError.invalidField("context")
        }
        sessionID = try object.requiredString("sessionID")
        messageID = try object.requiredString("messageID")
        agent = try object.requiredString("agent")
        directory = try object.requiredString("directory")
        worktree = try object.requiredString("worktree")
    }
}

struct OpenClientRemoteToolResult: Equatable, Sendable {
    let title: String?
    let output: String
    let metadata: [String: OpenClientJSONValue]?

    var jsonValue: OpenClientJSONValue {
        var object: [String: OpenClientJSONValue] = ["output": .string(output)]
        if let title { object["title"] = .string(title) }
        if let metadata { object["metadata"] = .object(metadata) }
        return .object(object)
    }
}

enum OpenClientBridgeRequestMethod: String, Codable, Sendable {
    case listTools = "list_tools"
    case executeTool = "execute_tool"
}

struct OpenClientBridgeRequest: Equatable, Sendable {
    let id: String
    let method: OpenClientBridgeRequestMethod
    let params: OpenClientJSONValue
}

enum OpenClientBridgeServerMessage: Equatable, Sendable {
    case registered(clientID: String)
    case request(OpenClientBridgeRequest)
    case cancel(id: String)
}

extension OpenClientBridgeServerMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case type
        case clientID
        case id
        case method
        case params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        guard protocolVersion == openClientBridgeProtocolVersion else {
            throw OpenClientBridgeProtocolError.unsupportedVersion(protocolVersion)
        }
        switch try container.decode(String.self, forKey: .type) {
        case "registered":
            self = .registered(clientID: try container.decode(String.self, forKey: .clientID))
        case "request":
            self = .request(
                OpenClientBridgeRequest(
                    id: try container.decode(String.self, forKey: .id),
                    method: try container.decode(OpenClientBridgeRequestMethod.self, forKey: .method),
                    params: try container.decode(OpenClientJSONValue.self, forKey: .params)
                )
            )
        case "cancel":
            self = .cancel(id: try container.decode(String.self, forKey: .id))
        default:
            throw OpenClientBridgeProtocolError.unsupportedMessage
        }
    }
}

struct OpenClientBridgeHealth: Decodable, Equatable, Sendable {
    let service: String
    let `protocol`: Int
    let port: Int
    let openCodePort: Int
}

enum OpenClientBridgeProtocolError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case unsupportedMessage
    case invalidField(String)
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return String(localized: "Unsupported OpenClient bridge protocol version \(version).")
        case .unsupportedMessage:
            return String(localized: "The OpenClient bridge sent an unsupported message.")
        case .invalidField(let field):
            return String(localized: "The OpenClient bridge message has an invalid \(field) field.")
        case .unknownTool(let toolID):
            return String(localized: "This OpenClient app does not support \(toolID).")
        }
    }
}

extension Dictionary where Key == String, Value == OpenClientJSONValue {
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key]?.stringValue, !value.isEmpty else {
            throw OpenClientBridgeProtocolError.invalidField(key)
        }
        return value
    }

    func object(_ key: String) throws -> [String: OpenClientJSONValue] {
        guard let value = self[key]?.objectValue else {
            throw OpenClientBridgeProtocolError.invalidField(key)
        }
        return value
    }
}
