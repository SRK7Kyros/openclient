import CryptoKit
import Foundation

enum OpenClientVisualHTMLContract {
    static let toolID = "openclient_visual_html"
    static let rendererID = "openclient.html.v1"
    static let schemaVersion = 1
    static let maximumHTMLBytes = 65_536
    static let maximumElementCount = 200
}

struct OpenClientVisualHTMLPayload: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let title: String
    let accessibilityLabel: String
    let html: String
    let height: Int

    var documentID: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func validated() throws -> OpenClientVisualHTMLPayload {
        guard schemaVersion == OpenClientVisualHTMLContract.schemaVersion else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.schemaVersion")
        }
        let title = try Self.normalized(title, maximumLength: 120, field: "arguments.title")
        let accessibilityLabel = try Self.normalized(
            accessibilityLabel,
            maximumLength: 500,
            field: "arguments.accessibilityLabel"
        )
        let html = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !html.isEmpty,
              html.lengthOfBytes(using: .utf8) <= OpenClientVisualHTMLContract.maximumHTMLBytes,
              Self.elementCount(in: html) <= OpenClientVisualHTMLContract.maximumElementCount,
              height > 0,
              Self.isSafeStaticFragment(html) else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.html")
        }

        return OpenClientVisualHTMLPayload(
            schemaVersion: OpenClientVisualHTMLContract.schemaVersion,
            title: title,
            accessibilityLabel: accessibilityLabel,
            html: html,
            height: height
        )
    }

    private static func normalized(_ value: String, maximumLength: Int, field: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= maximumLength,
              normalized.lengthOfBytes(using: .utf8) <= maximumLength * 4 else {
            throw OpenClientBridgeProtocolError.invalidField(field)
        }
        return normalized
    }

    private static func isSafeStaticFragment(_ html: String) -> Bool {
        let forbiddenPatterns = [
            #"<\s*/?\s*(script|iframe|frame|frameset|object|embed|form|input|button|select|option|textarea|label|base|link|meta|audio|video|source|track|foreignobject|a|img|image|use|filter|animate|animatetransform|animatemotion|set|canvas)(?:\s|/|>)"#,
            #"<\s*/?\s*fe[a-z0-9-]*(?:\s|/|>)"#,
            #"(?:\s|/)on[a-z]+\s*="#,
            #"(?:\s|/)(src|srcset|href|xlink:href|action|formaction|style)\s*="#,
            #"javascript\s*:"#,
            #"@import\b"#,
            #"@keyframes\b"#,
            #"(?:^|[;{\s])(animation|transition|filter|backdrop-filter)\s*:"#,
            #"url\s*\("#,
        ]
        guard !html.contains("\\") else { return false }
        return forbiddenPatterns.allSatisfy { pattern in
            html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
        }
    }

    private static func elementCount(in html: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: #"<\s*[a-zA-Z][^>]*>"#) else {
            return .max
        }
        return expression.numberOfMatches(
            in: html,
            range: NSRange(html.startIndex ..< html.endIndex, in: html)
        )
    }
}

extension OpenClientDeviceToolProvider {
    static var visualHTML: OpenClientDeviceToolProvider {
        OpenClientDeviceToolProvider(
            descriptor: OpenClientDeviceToolDescriptor(
                id: OpenClientVisualHTMLContract.toolID,
                description: "Display a sandboxed static HTML, inline CSS, or inline SVG visual in OpenClient chat. JavaScript, links, forms, frames, media, raster images, animation, filters, and external resources are not supported.",
                inputSchema: OpenClientVisualHTMLTool.inputSchema
            )
        ) { arguments, _ in
            let payload = try OpenClientVisualHTMLTool.decode(arguments: arguments).validated()
            let payloadValue = try OpenClientVisualHTMLTool.bridgeJSONValue(payload)
            return OpenClientRemoteToolResult(
                title: payload.title,
                output: "Displayed the static HTML visual \"\(payload.title)\".",
                metadata: [
                    "toolID": .string(OpenClientVisualHTMLContract.toolID),
                    "renderer": .string(OpenClientVisualHTMLContract.rendererID),
                    "schemaVersion": .number(Double(OpenClientVisualHTMLContract.schemaVersion)),
                    "payload": payloadValue,
                ]
            )
        }
    }
}

enum OpenClientVisualHTMLTool {
    static let inputSchema: [String: OpenClientJSONValue] = [
        "type": .string("object"),
        "required": .array([
            .string("schemaVersion"),
            .string("title"),
            .string("accessibilityLabel"),
            .string("html"),
            .string("height"),
        ]),
        "additionalProperties": .bool(false),
        "properties": .object([
            "schemaVersion": .object([
                "type": .string("integer"),
                "const": .number(Double(OpenClientVisualHTMLContract.schemaVersion)),
            ]),
            "title": textSchema(maximumLength: 120),
            "accessibilityLabel": .object([
                "type": .string("string"),
                "minLength": .number(1),
                "maxLength": .number(500),
                "pattern": .string("\\S"),
                "description": .string("A concise spoken description of the visual for VoiceOver and fallback clients."),
            ]),
            "html": .object([
                "type": .string("string"),
                "minLength": .number(1),
                "maxLength": .number(Double(OpenClientVisualHTMLContract.maximumHTMLBytes)),
                "description": .string("A static HTML fragment using inline CSS or simple inline SVG, with at most 200 elements. Scripts, event handlers, links, forms, frames, media, images, animation, filters, resource attributes, CSS imports, and CSS url() are rejected."),
            ]),
            "height": .object([
                "type": .string("integer"),
                "minimum": .number(1),
                "description": .string("The visual height in points. Use the full height needed by the page; there is no maximum."),
            ]),
        ]),
    ]

    static func decode(arguments: [String: OpenClientJSONValue]) throws -> OpenClientVisualHTMLPayload {
        do {
            guard Set(arguments.keys).isSubset(
                of: ["schemaVersion", "title", "accessibilityLabel", "html", "height"]
            ) else {
                throw OpenClientBridgeProtocolError.invalidField("arguments")
            }
            let data = try JSONEncoder().encode(OpenClientJSONValue.object(arguments))
            return try JSONDecoder().decode(OpenClientVisualHTMLPayload.self, from: data)
        } catch let error as OpenClientBridgeProtocolError {
            throw error
        } catch {
            throw OpenClientBridgeProtocolError.invalidField("arguments")
        }
    }

    static func bridgeJSONValue(_ payload: OpenClientVisualHTMLPayload) throws -> OpenClientJSONValue {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(OpenClientJSONValue.self, from: data)
    }

    private static func textSchema(maximumLength: Int) -> OpenClientJSONValue {
        .object([
            "type": .string("string"),
            "minLength": .number(1),
            "maxLength": .number(Double(maximumLength)),
            "pattern": .string("\\S"),
        ])
    }
}
