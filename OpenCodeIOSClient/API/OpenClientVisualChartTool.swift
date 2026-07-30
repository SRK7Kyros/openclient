import Foundation

enum OpenClientVisualChartContract {
    static let toolID = "openclient_visual_chart"
    static let rendererID = "openclient.chart.v1"
    static let schemaVersion = 1
    static let maximumSeries = 8
    static let maximumPoints = 500
}

enum OpenClientVisualChartType: String, Codable, CaseIterable, Hashable, Sendable {
    case line
    case area
    case bar
    case scatter
    case pie
    case donut
}

enum OpenClientVisualChartXAxisType: String, Codable, CaseIterable, Hashable, Sendable {
    case category
    case number
    case time
}

enum OpenClientVisualChartXValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

struct OpenClientVisualChartXAxis: Codable, Equatable, Hashable, Sendable {
    let type: OpenClientVisualChartXAxisType
    let title: String?
}

struct OpenClientVisualChartYAxis: Codable, Equatable, Hashable, Sendable {
    let title: String?
}

struct OpenClientVisualChartPoint: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let x: OpenClientVisualChartXValue
    let y: Double
}

struct OpenClientVisualChartSeries: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let points: [OpenClientVisualChartPoint]
}

struct OpenClientVisualChartPayload: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let chartType: OpenClientVisualChartType
    let title: String?
    let xAxis: OpenClientVisualChartXAxis
    let yAxis: OpenClientVisualChartYAxis
    let series: [OpenClientVisualChartSeries]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case chartType
        case title
        case xAxis
        case yAxis
        case series
    }

    init(
        schemaVersion: Int = OpenClientVisualChartContract.schemaVersion,
        chartType: OpenClientVisualChartType,
        title: String?,
        xAxis: OpenClientVisualChartXAxis,
        yAxis: OpenClientVisualChartYAxis = OpenClientVisualChartYAxis(title: nil),
        series: [OpenClientVisualChartSeries]
    ) {
        self.schemaVersion = schemaVersion
        self.chartType = chartType
        self.title = title
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.series = series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        chartType = try container.decode(OpenClientVisualChartType.self, forKey: .chartType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        xAxis = try container.decode(OpenClientVisualChartXAxis.self, forKey: .xAxis)
        yAxis = try container.decodeIfPresent(OpenClientVisualChartYAxis.self, forKey: .yAxis)
            ?? OpenClientVisualChartYAxis(title: nil)
        series = try container.decode([OpenClientVisualChartSeries].self, forKey: .series)
    }

    func validated() throws -> OpenClientVisualChartPayload {
        guard schemaVersion == OpenClientVisualChartContract.schemaVersion else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.schemaVersion")
        }
        guard !series.isEmpty, series.count <= OpenClientVisualChartContract.maximumSeries else {
            throw OpenClientBridgeProtocolError.invalidField("arguments.series")
        }

        let title = try Self.normalized(title, maximumLength: 120, field: "arguments.title")
        let xTitle = try Self.normalized(xAxis.title, maximumLength: 80, field: "arguments.xAxis.title")
        let yTitle = try Self.normalized(yAxis.title, maximumLength: 80, field: "arguments.yAxis.title")
        var seriesIDs: Set<String> = []
        var totalPointCount = 0

        let normalizedSeries = try series.map { series in
            let seriesID = try Self.requiredNormalized(
                series.id,
                maximumLength: 80,
                field: "arguments.series.id"
            )
            guard seriesIDs.insert(seriesID).inserted, !series.points.isEmpty else {
                throw OpenClientBridgeProtocolError.invalidField("arguments.series")
            }
            let name = try Self.requiredNormalized(
                series.name,
                maximumLength: 120,
                field: "arguments.series.name"
            )
            totalPointCount += series.points.count
            guard totalPointCount <= OpenClientVisualChartContract.maximumPoints else {
                throw OpenClientBridgeProtocolError.invalidField("arguments.series.points")
            }

            var pointIDs: Set<String> = []
            var xValues: Set<OpenClientVisualChartXValue> = []
            let points = try series.points.map { point in
                let pointID = try Self.requiredNormalized(
                    point.id,
                    maximumLength: 80,
                    field: "arguments.series.points.id"
                )
                guard pointIDs.insert(pointID).inserted, point.y.isFinite else {
                    throw OpenClientBridgeProtocolError.invalidField("arguments.series.points")
                }
                let x = try Self.normalizedXValue(point.x, axisType: xAxis.type)
                guard xValues.insert(x).inserted else {
                    throw OpenClientBridgeProtocolError.invalidField("arguments.series.points.x")
                }
                return OpenClientVisualChartPoint(id: pointID, x: x, y: point.y)
            }
            return OpenClientVisualChartSeries(id: seriesID, name: name, points: points)
        }

        if chartType == .pie || chartType == .donut {
            guard xAxis.type == .category, normalizedSeries.count == 1 else {
                throw OpenClientBridgeProtocolError.invalidField("arguments.series")
            }
            let values = normalizedSeries[0].points.map(\.y)
            let total = values.reduce(0, +)
            guard values.allSatisfy({ $0 >= 0 }), total.isFinite, total > 0 else {
                throw OpenClientBridgeProtocolError.invalidField("arguments.series.points.y")
            }
        }

        return OpenClientVisualChartPayload(
            chartType: chartType,
            title: title,
            xAxis: OpenClientVisualChartXAxis(type: xAxis.type, title: xTitle),
            yAxis: OpenClientVisualChartYAxis(title: yTitle),
            series: normalizedSeries
        )
    }

    var pointCount: Int {
        series.reduce(0) { $0 + $1.points.count }
    }

    private static func normalizedXValue(
        _ value: OpenClientVisualChartXValue,
        axisType: OpenClientVisualChartXAxisType
    ) throws -> OpenClientVisualChartXValue {
        switch (axisType, value) {
        case (.category, .string(let value)):
            return .string(try requiredNormalized(value, maximumLength: 120, field: "arguments.series.points.x"))
        case (.time, .string(let value)):
            let normalized = try requiredNormalized(value, maximumLength: 80, field: "arguments.series.points.x")
            guard OpenClientVisualChartTool.date(from: normalized) != nil else {
                throw OpenClientBridgeProtocolError.invalidField("arguments.series.points.x")
            }
            return .string(normalized)
        case (.number, .number(let value)) where value.isFinite:
            return .number(value)
        default:
            throw OpenClientBridgeProtocolError.invalidField("arguments.series.points.x")
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
    static var visualChart: OpenClientDeviceToolProvider {
        OpenClientDeviceToolProvider(
            descriptor: OpenClientDeviceToolDescriptor(
                id: OpenClientVisualChartContract.toolID,
                description: "Display a native chart in the OpenClient chat. Supports line, area, bar, scatter, pie, and donut charts with categorical, numeric, or RFC 3339 timestamp axes.",
                inputSchema: OpenClientVisualChartTool.inputSchema
            )
        ) { arguments, _ in
            let payload = try OpenClientVisualChartTool.decode(arguments: arguments).validated()
            let payloadValue = try OpenClientVisualChartTool.bridgeJSONValue(payload)
            let chartName = payload.chartType.rawValue
            let pointDescription = payload.pointCount == 1 ? "1 data point" : "\(payload.pointCount) data points"
            return OpenClientRemoteToolResult(
                title: payload.title ?? "Chart",
                output: "Displayed a \(chartName) chart with \(pointDescription).",
                metadata: [
                    "toolID": .string(OpenClientVisualChartContract.toolID),
                    "renderer": .string(OpenClientVisualChartContract.rendererID),
                    "schemaVersion": .number(Double(OpenClientVisualChartContract.schemaVersion)),
                    "payload": payloadValue,
                ]
            )
        }
    }
}

enum OpenClientVisualChartTool {
    static let inputSchema: [String: OpenClientJSONValue] = [
        "type": .string("object"),
        "required": .array([
            .string("schemaVersion"),
            .string("chartType"),
            .string("xAxis"),
            .string("series"),
        ]),
        "additionalProperties": .bool(false),
        "properties": .object([
            "schemaVersion": .object([
                "type": .string("integer"),
                "const": .number(Double(OpenClientVisualChartContract.schemaVersion)),
            ]),
            "chartType": enumSchema(OpenClientVisualChartType.allCases.map(\.rawValue)),
            "title": textSchema(maximumLength: 120),
            "xAxis": .object([
                "type": .string("object"),
                "required": .array([.string("type")]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "type": enumSchema(OpenClientVisualChartXAxisType.allCases.map(\.rawValue)),
                    "title": textSchema(maximumLength: 80),
                ]),
            ]),
            "yAxis": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "title": textSchema(maximumLength: 80),
                ]),
            ]),
            "series": .object([
                "type": .string("array"),
                "minItems": .number(1),
                "maxItems": .number(Double(OpenClientVisualChartContract.maximumSeries)),
                "items": .object([
                    "type": .string("object"),
                    "required": .array([.string("id"), .string("name"), .string("points")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "id": textSchema(maximumLength: 80),
                        "name": textSchema(maximumLength: 120),
                        "points": .object([
                            "type": .string("array"),
                            "description": .string("Chart points. The aggregate limit across all series is 500 points."),
                            "minItems": .number(1),
                            "maxItems": .number(Double(OpenClientVisualChartContract.maximumPoints)),
                            "items": .object([
                                "type": .string("object"),
                                "required": .array([.string("id"), .string("x"), .string("y")]),
                                "additionalProperties": .bool(false),
                                "properties": .object([
                                    "id": textSchema(maximumLength: 80),
                                    "x": .object([
                                        "oneOf": .array([
                                            .object(["type": .string("string")]),
                                            .object(["type": .string("number")]),
                                        ]),
                                    ]),
                                    "y": .object(["type": .string("number")]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ]

    static func decode(arguments: [String: OpenClientJSONValue]) throws -> OpenClientVisualChartPayload {
        do {
            try validateShape(arguments)
            let data = try JSONEncoder().encode(OpenClientJSONValue.object(arguments))
            return try JSONDecoder().decode(OpenClientVisualChartPayload.self, from: data)
        } catch let error as OpenClientBridgeProtocolError {
            throw error
        } catch {
            throw OpenClientBridgeProtocolError.invalidField("arguments")
        }
    }

    static func bridgeJSONValue(_ payload: OpenClientVisualChartPayload) throws -> OpenClientJSONValue {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(OpenClientJSONValue.self, from: data)
    }

    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func enumSchema(_ values: [String]) -> OpenClientJSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(OpenClientJSONValue.string)),
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
            allowed: ["schemaVersion", "chartType", "title", "xAxis", "yAxis", "series"],
            field: "arguments"
        )
        if let xAxis = arguments["xAxis"]?.objectValue {
            try rejectUnknownKeys(in: xAxis, allowed: ["type", "title"], field: "arguments.xAxis")
        }
        if let yAxis = arguments["yAxis"]?.objectValue {
            try rejectUnknownKeys(in: yAxis, allowed: ["title"], field: "arguments.yAxis")
        }
        if case let .array(seriesValues)? = arguments["series"] {
            for seriesValue in seriesValues {
                guard let series = seriesValue.objectValue else {
                    throw OpenClientBridgeProtocolError.invalidField("arguments.series")
                }
                try rejectUnknownKeys(
                    in: series,
                    allowed: ["id", "name", "points"],
                    field: "arguments.series"
                )
                if case let .array(pointValues)? = series["points"] {
                    for pointValue in pointValues {
                        guard let point = pointValue.objectValue else {
                            throw OpenClientBridgeProtocolError.invalidField("arguments.series.points")
                        }
                        try rejectUnknownKeys(
                            in: point,
                            allowed: ["id", "x", "y"],
                            field: "arguments.series.points"
                        )
                    }
                }
            }
        }
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
