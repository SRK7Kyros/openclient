import Foundation
#if canImport(UIKit)
import UIKit
typealias OpenClientPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias OpenClientPlatformImage = NSImage
#endif

enum OpenClientVisualPreviewError: LocalizedError, Equatable {
    case invalidMIMEType
    case invalidDataURL
    case exceedsSizeLimit
    case invalidJPEG
    case invalidDimensions

    var errorDescription: String? {
        switch self {
        case .invalidMIMEType:
            return String(localized: "The visual preview must be a JPEG image.")
        case .invalidDataURL:
            return String(localized: "The visual preview data URL is invalid.")
        case .exceedsSizeLimit:
            return String(localized: "The visual preview exceeds the supported size limit.")
        case .invalidJPEG:
            return String(localized: "The visual preview is not a valid JPEG image.")
        case .invalidDimensions:
            return String(localized: "The visual preview dimensions are invalid.")
        }
    }
}

final class OpenClientVisualPreview: Codable, Equatable, Hashable, @unchecked Sendable {
    static let mimeType = "image/jpeg"
    static let dataURLPrefix = "data:image/jpeg;base64,"
    static let maximumDecodedBytes = 32 * 1_024
    static let maximumDimension = 96

    let mimeType: String
    let dataURL: String
    let width: Int
    let height: Int
    let data: Data
    let platformImage: OpenClientPlatformImage

    init(mimeType: String, dataURL: String, width: Int, height: Int) throws {
        guard mimeType == Self.mimeType else {
            throw OpenClientVisualPreviewError.invalidMIMEType
        }
        guard width > 0, height > 0,
              width <= Self.maximumDimension, height <= Self.maximumDimension else {
            throw OpenClientVisualPreviewError.invalidDimensions
        }
        guard dataURL.hasPrefix(Self.dataURLPrefix) else {
            throw OpenClientVisualPreviewError.invalidDataURL
        }

        let encoded = String(dataURL.dropFirst(Self.dataURLPrefix.count))
        let maximumEncodedLength = ((Self.maximumDecodedBytes + 2) / 3) * 4
        guard !encoded.isEmpty else {
            throw OpenClientVisualPreviewError.invalidDataURL
        }
        guard encoded.count <= maximumEncodedLength else {
            throw OpenClientVisualPreviewError.exceedsSizeLimit
        }
        guard encoded.unicodeScalars.allSatisfy(Self.isBase64Scalar),
              encoded.count.isMultiple(of: 4) else {
            throw OpenClientVisualPreviewError.invalidDataURL
        }
        if let cached = Self.decodedCache.value(dataURL: dataURL, width: width, height: height) {
            self.mimeType = mimeType
            self.dataURL = dataURL
            self.width = width
            self.height = height
            data = cached.data
            platformImage = cached.image
            return
        }
        guard let decoded = Data(base64Encoded: encoded),
              decoded.base64EncodedString() == encoded else {
            throw OpenClientVisualPreviewError.invalidDataURL
        }
        guard !decoded.isEmpty, decoded.count <= Self.maximumDecodedBytes else {
            throw OpenClientVisualPreviewError.exceedsSizeLimit
        }
        guard decoded.count >= 4,
              decoded[decoded.startIndex] == 0xff,
              decoded[decoded.startIndex + 1] == 0xd8,
              decoded[decoded.endIndex - 2] == 0xff,
              decoded[decoded.endIndex - 1] == 0xd9,
              let image = OpenClientPlatformImageDecoder.decode(decoded) else {
            throw OpenClientVisualPreviewError.invalidJPEG
        }
        guard image.width == width, image.height == height else {
            throw OpenClientVisualPreviewError.invalidDimensions
        }

        self.mimeType = mimeType
        self.dataURL = dataURL
        self.width = width
        self.height = height
        data = decoded
        platformImage = image.image
        Self.decodedCache.insert(
            dataURL: dataURL,
            width: width,
            height: height,
            data: decoded,
            image: image.image
        )
    }

    convenience init(jpegData: Data, width: Int, height: Int) throws {
        try self.init(
            mimeType: Self.mimeType,
            dataURL: Self.dataURLPrefix + jpegData.base64EncodedString(),
            width: width,
            height: height
        )
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            mimeType: container.decode(String.self, forKey: .mimeType),
            dataURL: container.decode(String.self, forKey: .dataURL),
            width: container.decode(Int.self, forKey: .width),
            height: container.decode(Int.self, forKey: .height)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(dataURL, forKey: .dataURL)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }

    static func == (lhs: OpenClientVisualPreview, rhs: OpenClientVisualPreview) -> Bool {
        lhs.mimeType == rhs.mimeType
            && lhs.dataURL == rhs.dataURL
            && lhs.width == rhs.width
            && lhs.height == rhs.height
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(mimeType)
        hasher.combine(dataURL)
        hasher.combine(width)
        hasher.combine(height)
    }

    private enum CodingKeys: String, CodingKey {
        case mimeType
        case dataURL
        case width
        case height
    }

    private static func isBase64Scalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 43, 47, 48 ... 57, 61, 65 ... 90, 97 ... 122:
            return true
        default:
            return false
        }
    }

    private static let decodedCache = OpenClientVisualPreviewCache()
}

private final class OpenClientVisualPreviewCache: @unchecked Sendable {
    private let cache = NSCache<NSString, OpenClientVisualPreviewStorage>()

    init() {
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1_024 * 1_024
    }

    func value(dataURL: String, width: Int, height: Int) -> OpenClientVisualPreviewStorage? {
        cache.object(forKey: key(dataURL: dataURL, width: width, height: height))
    }

    func insert(
        dataURL: String,
        width: Int,
        height: Int,
        data: Data,
        image: OpenClientPlatformImage
    ) {
        cache.setObject(
            OpenClientVisualPreviewStorage(data: data, image: image),
            forKey: key(dataURL: dataURL, width: width, height: height),
            cost: data.count
        )
    }

    private func key(dataURL: String, width: Int, height: Int) -> NSString {
        "\(width)x\(height):\(dataURL)" as NSString
    }
}

private final class OpenClientVisualPreviewStorage {
    let data: Data
    let image: OpenClientPlatformImage

    init(data: Data, image: OpenClientPlatformImage) {
        self.data = data
        self.image = image
    }
}

struct OpenClientDecodedPlatformImage: @unchecked Sendable {
    let image: OpenClientPlatformImage
    let width: Int
    let height: Int
}

enum OpenClientPlatformImageDecoder {
    static func decode(_ data: Data) -> OpenClientDecodedPlatformImage? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        return OpenClientDecodedPlatformImage(image: image, width: cgImage.width, height: cgImage.height)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        return OpenClientDecodedPlatformImage(image: image, width: cgImage.width, height: cgImage.height)
        #endif
    }
}
