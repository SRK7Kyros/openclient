import Foundation

enum OpenClientVisualMapContract {
    static let toolID = "openclient_visual_map"
    static let rendererID = "openclient.map.v1"
    static let schemaVersion = 1
    static let maximumMarkers = 50
}

struct OpenClientVisualMapCoordinate: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct OpenClientVisualMapSpan: Codable, Equatable, Hashable, Sendable {
    let latitudeDelta: Double
    let longitudeDelta: Double

    static let defaultValue = OpenClientVisualMapSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
}

struct OpenClientVisualMapMarker: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let coordinate: OpenClientVisualMapCoordinate
}

struct OpenClientVisualMapPayload: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let title: String?
    let center: OpenClientVisualMapCoordinate
    let span: OpenClientVisualMapSpan
    let markers: [OpenClientVisualMapMarker]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case title
        case center
        case span
        case markers
    }

    init(
        schemaVersion: Int = OpenClientVisualMapContract.schemaVersion,
        title: String?,
        center: OpenClientVisualMapCoordinate,
        span: OpenClientVisualMapSpan = .defaultValue,
        markers: [OpenClientVisualMapMarker] = []
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.center = center
        self.span = span
        self.markers = markers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        center = try container.decode(OpenClientVisualMapCoordinate.self, forKey: .center)
        span = try container.decodeIfPresent(OpenClientVisualMapSpan.self, forKey: .span) ?? .defaultValue
        markers = try container.decodeIfPresent([OpenClientVisualMapMarker].self, forKey: .markers) ?? []
    }

    func validated() throws -> OpenClientVisualMapPayload {
        guard schemaVersion == OpenClientVisualMapContract.schemaVersion else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.schemaVersion")
        }
        try Self.validate(center, field: "arguments.center")
        guard span.latitudeDelta >= 0.0001, span.latitudeDelta <= 180,
              span.longitudeDelta >= 0.0001, span.longitudeDelta <= 360 else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.span")
        }
        guard markers.count <= OpenClientVisualMapContract.maximumMarkers else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.markers")
        }

        let normalizedTitle = try Self.normalized(title, maximumLength: 120, field: "arguments.title")
        var markerIDs: Set<String> = []
        let normalizedMarkers = try markers.map { marker in
            let id = try Self.requiredNormalized(marker.id, maximumLength: 80, field: "arguments.markers.id")
            guard markerIDs.insert(id).inserted else {
                throw OpenClientBridgeProtocolError.invalidField("arguments.markers.id")
            }
            let title = try Self.requiredNormalized(marker.title, maximumLength: 120, field: "arguments.markers.title")
            let subtitle = try Self.normalized(marker.subtitle, maximumLength: 240, field: "arguments.markers.subtitle")
            try Self.validate(marker.coordinate, field: "arguments.markers.coordinate")
            return OpenClientVisualMapMarker(
                id: id,
                title: title,
                subtitle: subtitle,
                coordinate: marker.coordinate
            )
        }

        return OpenClientVisualMapPayload(
            title: normalizedTitle,
            center: center,
            span: span,
            markers: normalizedMarkers
        )
    }

    private static func validate(_ coordinate: OpenClientVisualMapCoordinate, field: String) throws {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90 ... 90).contains(coordinate.latitude),
              (-180 ... 180).contains(coordinate.longitude) else {
            throw OpenClientBridgeProtocolError.invalidField(field)
        }
    }

    private static func normalized(_ value: String?, maximumLength: Int, field: String) throws -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= maximumLength else {
            throw OpenClientBridgeProtocolError.invalidField(field)
        }
        return normalized
    }

    private static func requiredNormalized(_ value: String, maximumLength: Int, field: String) throws -> String {
        guard let normalized = try normalized(value, maximumLength: maximumLength, field: field) else {
            throw OpenClientBridgeProtocolError.invalidField(field)
        }
        return normalized
    }
}

extension OpenClientDeviceToolProvider {
    static var visualMap: OpenClientDeviceToolProvider {
        OpenClientDeviceToolProvider(
            descriptor: OpenClientDeviceToolDescriptor(
                id: OpenClientVisualMapContract.toolID,
                description: "Display a native interactive map in the OpenClient chat. Provide a center coordinate and optional markers; use this when geographic context is clearer visually than as text.",
                inputSchema: OpenClientVisualMapTool.inputSchema
            )
        ) { arguments, _ in
            let payload = try OpenClientVisualMapTool.decode(arguments: arguments).validated()
            let payloadValue = try OpenClientVisualMapTool.bridgeJSONValue(payload)
            let markerDescription = payload.markers.count == 1 ? "1 marker" : "\(payload.markers.count) markers"
            let location = payload.title ?? String(
                format: "%.5f, %.5f",
                payload.center.latitude,
                payload.center.longitude
            )
            return OpenClientRemoteToolResult(
                title: payload.title ?? "Map",
                output: "Displayed \(location) with \(markerDescription).",
                metadata: [
                    "toolID": .string(OpenClientVisualMapContract.toolID),
                    "renderer": .string(OpenClientVisualMapContract.rendererID),
                    "schemaVersion": .number(Double(OpenClientVisualMapContract.schemaVersion)),
                    "payload": payloadValue,
                ]
            )
        }
    }
}

enum OpenClientVisualMapTool {
    static let inputSchema: [String: OpenClientJSONValue] = [
        "type": .string("object"),
        "required": .array([.string("schemaVersion"), .string("center")]),
        "additionalProperties": .bool(false),
        "properties": .object([
            "schemaVersion": .object([
                "type": .string("integer"),
                "const": .number(Double(OpenClientVisualMapContract.schemaVersion)),
            ]),
            "title": .object([
                "type": .string("string"),
                "minLength": .number(1),
                "maxLength": .number(120),
                "pattern": .string("\\S"),
                "description": .string("A short title shown above the map."),
            ]),
            "center": coordinateSchema(description: "The initial center of the map."),
            "span": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([.string("latitudeDelta"), .string("longitudeDelta")]),
                "properties": .object([
                    "latitudeDelta": .object([
                        "type": .string("number"),
                        "minimum": .number(0.0001),
                        "maximum": .number(180),
                    ]),
                    "longitudeDelta": .object([
                        "type": .string("number"),
                        "minimum": .number(0.0001),
                        "maximum": .number(360),
                    ]),
                ]),
            ]),
            "markers": .object([
                "type": .string("array"),
                "maxItems": .number(Double(OpenClientVisualMapContract.maximumMarkers)),
                "items": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("id"), .string("title"), .string("coordinate")]),
                    "properties": .object([
                        "id": textSchema(maximumLength: 80),
                        "title": textSchema(maximumLength: 120),
                        "subtitle": textSchema(maximumLength: 240),
                        "coordinate": coordinateSchema(description: "The marker location."),
                    ]),
                ]),
            ]),
        ]),
    ]

    static func decode(arguments: [String: OpenClientJSONValue]) throws -> OpenClientVisualMapPayload {
        do {
            try validateShape(arguments)
            let data = try JSONEncoder().encode(OpenClientJSONValue.object(arguments))
            return try JSONDecoder().decode(OpenClientVisualMapPayload.self, from: data)
        } catch let error as OpenClientBridgeProtocolError {
            throw error
        } catch {
            throw OpenClientBridgeProtocolError.invalidField("arguments")
        }
    }

    static func bridgeJSONValue(_ payload: OpenClientVisualMapPayload) throws -> OpenClientJSONValue {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(OpenClientJSONValue.self, from: data)
    }

    private static func coordinateSchema(description: String) -> OpenClientJSONValue {
        .object([
            "type": .string("object"),
            "description": .string(description),
            "additionalProperties": .bool(false),
            "required": .array([.string("latitude"), .string("longitude")]),
            "properties": .object([
                "latitude": .object([
                    "type": .string("number"),
                    "minimum": .number(-90),
                    "maximum": .number(90),
                ]),
                "longitude": .object([
                    "type": .string("number"),
                    "minimum": .number(-180),
                    "maximum": .number(180),
                ]),
            ]),
        ])
    }

    private static func textSchema(maximumLength: Int) -> OpenClientJSONValue {
        .object([
            "type": .string("string"),
            "minLength": .number(1),
            "maxLength": .number(Double(maximumLength)),
            "pattern": .string("\\S"),
        ])
    }

    private static func validateShape(_ arguments: [String: OpenClientJSONValue]) throws {
        try rejectUnknownKeys(
            in: arguments,
            allowed: ["schemaVersion", "title", "center", "span", "markers"],
            field: "arguments"
        )
        if let center = arguments["center"]?.objectValue {
            try validateCoordinateShape(center, field: "arguments.center")
        }
        if let span = arguments["span"]?.objectValue {
            try rejectUnknownKeys(
                in: span,
                allowed: ["latitudeDelta", "longitudeDelta"],
                field: "arguments.span"
            )
        }
        if case let .array(markers)? = arguments["markers"] {
            for markerValue in markers {
                guard let marker = markerValue.objectValue else {
                    throw OpenClientBridgeProtocolError.invalidField("arguments.markers")
                }
                try rejectUnknownKeys(
                    in: marker,
                    allowed: ["id", "title", "subtitle", "coordinate"],
                    field: "arguments.markers"
                )
                if let coordinate = marker["coordinate"]?.objectValue {
                    try validateCoordinateShape(coordinate, field: "arguments.markers.coordinate")
                }
            }
        }
    }

    private static func validateCoordinateShape(
        _ coordinate: [String: OpenClientJSONValue],
        field: String
    ) throws {
        try rejectUnknownKeys(
            in: coordinate,
            allowed: ["latitude", "longitude"],
            field: field
        )
    }

    private static func rejectUnknownKeys(
        in object: [String: OpenClientJSONValue],
        allowed: Set<String>,
        field: String
    ) throws {
        guard Set(object.keys).isSubset(of: allowed) else {
            throw OpenClientBridgeProtocolError.invalidField(field)
        }
    }
}
