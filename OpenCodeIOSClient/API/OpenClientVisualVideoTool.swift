import Foundation

enum OpenClientVisualVideoContract {
    static let toolID = "openclient_visual_video"
    static let rendererID = "openclient.video.v1"
    static let schemaVersion = 1
    static let maximumFileBytes: Int64 = 20 * 1_024 * 1_024 * 1_024
}

struct OpenClientVisualVideoFile: Codable, Equatable, Hashable, Sendable {
    let name: String
    let sizeBytes: Int64
    let modifiedAt: String
    let mimeType: String
}

struct OpenClientVisualVideoPayload: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let title: String?
    let resourceID: String
    let startPath: String
    let stopPath: String
    let expiresAt: String
    let file: OpenClientVisualVideoFile
    var width: Int? = nil
    var height: Int? = nil
    var rotation: Int? = nil
    var duration: Double? = nil
    var cover: OpenClientVisualPreview? = nil

    var displayTitle: String {
        title ?? file.name
    }

    var displayAspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 16 / 9 }
        let swapsDimensions = rotation == 90 || rotation == 270
        let displayWidth = swapsDimensions ? height : width
        let displayHeight = swapsDimensions ? width : height
        return CGFloat(displayWidth) / CGFloat(displayHeight)
    }

    func validated() throws -> OpenClientVisualVideoPayload {
        guard schemaVersion == OpenClientVisualVideoContract.schemaVersion else {
            throw OpenClientBridgeProtocolError.invalidField("payload.schemaVersion")
        }
        guard resourceID.utf8.count == 32,
              resourceID.utf8.allSatisfy(Self.isOpaqueIDByte) else {
            throw OpenClientBridgeProtocolError.invalidField("payload.resourceID")
        }
        let expectedPath = "/openclient/v1/video/resources/\(resourceID)/stream"
        guard startPath == expectedPath, stopPath == expectedPath else {
            throw OpenClientBridgeProtocolError.invalidField("payload.startPath")
        }
        guard Self.date(from: expiresAt) != nil else {
            throw OpenClientBridgeProtocolError.invalidField("payload.expiresAt")
        }
        guard !file.name.isEmpty,
               file.name.count <= 255,
               !file.name.contains("/"),
               !file.name.contains("\\"),
               URL(fileURLWithPath: file.name).pathExtension.lowercased() == "mp4",
               file.sizeBytes > 0,
               file.sizeBytes <= OpenClientVisualVideoContract.maximumFileBytes,
               file.mimeType == "video/mp4",
               Self.date(from: file.modifiedAt) != nil else {
            throw OpenClientBridgeProtocolError.invalidField("payload.file")
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle?.isEmpty != true, normalizedTitle?.unicodeScalars.count ?? 0 <= 120 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.title")
        }
        guard let width, width > 0 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.width")
        }
        guard let height, height > 0 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.height")
        }
        guard let rotation, [0, 90, 180, 270].contains(rotation) else {
            throw OpenClientBridgeProtocolError.invalidField("payload.rotation")
        }
        guard let duration, duration.isFinite, duration >= 0 else {
            throw OpenClientBridgeProtocolError.invalidField("payload.duration")
        }
        guard let cover else {
            throw OpenClientBridgeProtocolError.invalidField("payload.cover")
        }
        return OpenClientVisualVideoPayload(
            schemaVersion: OpenClientVisualVideoContract.schemaVersion,
            title: normalizedTitle,
            resourceID: resourceID,
            startPath: startPath,
            stopPath: stopPath,
            expiresAt: expiresAt,
            file: file,
            width: width,
            height: height,
            rotation: rotation,
            duration: duration,
            cover: cover
        )
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
