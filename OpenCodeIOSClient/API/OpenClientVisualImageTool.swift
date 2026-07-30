import Foundation

enum OpenClientVisualImageContract {
    static let toolID = "openclient_visual_image"
    static let rendererID = "openclient.image.v1"
    static let schemaVersion = 1
    static let maximumFileBytes: Int64 = 20 * 1_024 * 1_024
}

struct OpenClientVisualImageFile: Codable, Equatable, Hashable, Sendable {
    let name: String
    let sizeBytes: Int64
    let modifiedAt: String
    let mimeType: String
}

struct OpenClientVisualImagePayload: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let title: String?
    let accessibilityLabel: String?
    let resourceID: String
    let contentPath: String
    let expiresAt: String
    let width: Int
    let height: Int
    let file: OpenClientVisualImageFile
    let preview: OpenClientVisualPreview

    var displayTitle: String {
        title ?? file.name
    }

    var displayAspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }

    func validated() throws -> OpenClientVisualImagePayload {
        guard schemaVersion == OpenClientVisualImageContract.schemaVersion else {
            throw OpenClientBridgeProtocolError.invalidField("payload.schemaVersion")
        }
        guard resourceID.utf8.count == 32,
              resourceID.utf8.allSatisfy(Self.isOpaqueIDByte) else {
            throw OpenClientBridgeProtocolError.invalidField("payload.resourceID")
        }
        guard contentPath == "/openclient/v1/image/resources/\(resourceID)/content" else {
            throw OpenClientBridgeProtocolError.invalidField("payload.contentPath")
        }
        guard Self.date(from: expiresAt) != nil else {
            throw OpenClientBridgeProtocolError.invalidField("payload.expiresAt")
        }
        guard width > 0, height > 0 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.dimensions")
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle?.isEmpty != true, normalizedTitle?.unicodeScalars.count ?? 0 <= 120 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.title")
        }
        let normalizedAccessibilityLabel = accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedAccessibilityLabel?.isEmpty != true,
              normalizedAccessibilityLabel?.unicodeScalars.count ?? 0 <= 500 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.accessibilityLabel")
        }
        guard Self.isValid(file: file) else {
            throw OpenClientBridgeProtocolError.invalidField("payload.file")
        }

        return OpenClientVisualImagePayload(
            schemaVersion: OpenClientVisualImageContract.schemaVersion,
            title: normalizedTitle,
            accessibilityLabel: normalizedAccessibilityLabel,
            resourceID: resourceID,
            contentPath: contentPath,
            expiresAt: expiresAt,
            width: width,
            height: height,
            file: file,
            preview: preview
        )
    }

    private static func isValid(file: OpenClientVisualImageFile) -> Bool {
        guard !file.name.isEmpty,
              file.name.count <= 255,
              !file.name.contains("/"),
              !file.name.contains("\\"),
              !file.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              file.sizeBytes > 0,
              file.sizeBytes <= OpenClientVisualImageContract.maximumFileBytes,
              date(from: file.modifiedAt) != nil else {
            return false
        }

        let fileExtension = URL(fileURLWithPath: file.name).pathExtension.lowercased()
        switch file.mimeType {
        case "image/jpeg":
            return fileExtension == "jpg" || fileExtension == "jpeg"
        case "image/png":
            return fileExtension == "png"
        case "image/webp":
            return fileExtension == "webp"
        default:
            return false
        }
    }

    private static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func isOpaqueIDByte(_ byte: UInt8) -> Bool {
        (48 ... 57).contains(byte)
            || (65 ... 90).contains(byte)
            || byte == 95
            || (97 ... 122).contains(byte)
            || byte == 45
    }
}
