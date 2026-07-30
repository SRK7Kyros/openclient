import Charts
import SwiftUI

struct OpenClientVisualChartActivity: Equatable {
    let payload: OpenClientVisualChartPayload
    let status: String
    let errorMessage: String?

    init(payload: OpenClientVisualChartPayload, status: String = "completed", errorMessage: String? = nil) {
        self.payload = payload
        self.status = status
        self.errorMessage = errorMessage
    }

    init?(part: OpenCodePart) {
        guard part.type == "tool",
              part.tool == "openclient_execute_tool",
              let state = part.state,
              state.input?.toolID == OpenClientVisualChartContract.toolID else {
            return nil
        }

        let payloadValue: OpenCodeJSONValue?
        if state.metadata?.renderer == OpenClientVisualChartContract.rendererID {
            payloadValue = state.metadata?.payload
        } else if let arguments = state.input?.arguments {
            payloadValue = .object(arguments)
        } else {
            payloadValue = nil
        }
        guard let payloadValue,
              let data = try? JSONEncoder().encode(payloadValue),
              let decoded = try? JSONDecoder().decode(OpenClientVisualChartPayload.self, from: data),
              let payload = try? decoded.validated() else {
            return nil
        }

        self.payload = payload
        status = state.status?.lowercased() ?? "pending"
        errorMessage = state.error
    }

    var isRunning: Bool {
        status == "pending" || status == "running" || status == "in_progress"
    }
}

struct OpenClientVisualChartView: View {
    let activity: OpenClientVisualChartActivity
    let contentHeight: CGFloat

    init(activity: OpenClientVisualChartActivity, contentHeight: CGFloat = 230) {
        self.activity = activity
        self.contentHeight = contentHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OpenClientVisualChartHeader(
                title: activity.payload.title ?? activity.payload.chartType.displayName,
                subtitle: activity.payload.summary,
                isRunning: activity.isRunning
            )
            .padding(12)

            OpenClientVisualChartContent(payload: activity.payload)
                .id(activity.payload)
                .frame(height: contentHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .accessibilityIdentifier("chat.tool.visual-chart")

            if let errorMessage = activity.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
            }
        }
        .background(OpenCodePlatformColor.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

private struct OpenClientVisualChartHeader: View {
    let title: String
    let subtitle: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 28, height: 28)
                .background(.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct OpenClientVisualChartContent: View {
    let payload: OpenClientVisualChartPayload

    @ViewBuilder
    var body: some View {
        switch payload.chartType {
        case .pie, .donut:
            OpenClientSectorChart(payload: payload)
        case .line, .area, .bar, .scatter:
            OpenClientCartesianChart(payload: payload)
        }
    }
}

private struct OpenClientCartesianChart: View {
    let payload: OpenClientVisualChartPayload

    @ViewBuilder
    var body: some View {
        switch payload.xAxis.type {
        case .category:
            OpenClientTypedCartesianChart<String>(
                payload: payload,
                data: payload.cartesianData { value in
                    guard case .string(let value) = value else { return nil }
                    return value
                }
            )
        case .number:
            OpenClientTypedCartesianChart<Double>(
                payload: payload,
                data: payload.cartesianData { value in
                    guard case .number(let value) = value else { return nil }
                    return value
                }
            )
        case .time:
            OpenClientTypedCartesianChart<Date>(
                payload: payload,
                data: payload.cartesianData { value in
                    guard case .string(let value) = value else { return nil }
                    return OpenClientVisualChartTool.date(from: value)
                }
            )
        }
    }
}

private struct OpenClientCartesianDatum<X: Plottable & Hashable>: Identifiable {
    struct ID: Hashable {
        let seriesID: String
        let pointID: String
    }

    let id: ID
    let seriesID: String
    let seriesName: String
    let x: X
    let y: Double
}

private struct OpenClientTypedCartesianChart<X: Plottable & Hashable>: View {
    let payload: OpenClientVisualChartPayload
    let data: [OpenClientCartesianDatum<X>]

    @ViewBuilder
    var body: some View {
        switch payload.chartType {
        case .line:
            Chart(data) { datum in
                LineMark(
                    x: .value(payload.xAxis.title ?? "X", datum.x),
                    y: .value(payload.yAxis.title ?? "Y", datum.y),
                    series: .value("Series ID", datum.seriesID)
                )
                .foregroundStyle(by: .value("Series", datum.seriesName))
            }
            .chartPresentation(payload: payload)
        case .area:
            Chart(data) { datum in
                AreaMark(
                    x: .value(payload.xAxis.title ?? "X", datum.x),
                    y: .value(payload.yAxis.title ?? "Y", datum.y),
                    series: .value("Series ID", datum.seriesID)
                )
                .foregroundStyle(by: .value("Series", datum.seriesName))
            }
            .chartPresentation(payload: payload)
        case .bar:
            Chart(data) { datum in
                BarMark(
                    x: .value(payload.xAxis.title ?? "X", datum.x),
                    y: .value(payload.yAxis.title ?? "Y", datum.y)
                )
                .foregroundStyle(by: .value("Series", datum.seriesName))
            }
            .chartPresentation(payload: payload)
        case .scatter:
            Chart(data) { datum in
                PointMark(
                    x: .value(payload.xAxis.title ?? "X", datum.x),
                    y: .value(payload.yAxis.title ?? "Y", datum.y)
                )
                .foregroundStyle(by: .value("Series", datum.seriesName))
            }
            .chartPresentation(payload: payload)
        case .pie, .donut:
            EmptyView()
        }
    }
}

private extension View {
    func chartPresentation(payload: OpenClientVisualChartPayload) -> some View {
        chartXAxisLabel(payload.xAxis.title ?? "")
            .chartYAxisLabel(payload.yAxis.title ?? "")
            .chartLegend(payload.series.count > 1 ? .visible : .hidden)
    }
}

private struct OpenClientSectorDatum: Identifiable {
    let id: String
    let category: String
    let value: Double
}

private struct OpenClientSectorChart: View {
    let payload: OpenClientVisualChartPayload

    private var data: [OpenClientSectorDatum] {
        guard let series = payload.series.first else { return [] }
        return series.points.compactMap { point in
            guard case .string(let category) = point.x else { return nil }
            return OpenClientSectorDatum(id: point.id, category: category, value: point.y)
        }
    }

    var body: some View {
        Chart(data) { datum in
            SectorMark(
                angle: .value(payload.yAxis.title ?? "Value", datum.value),
                innerRadius: .ratio(payload.chartType == .donut ? 0.55 : 0),
                angularInset: 1.5
            )
            .foregroundStyle(by: .value("Category", datum.category))
            .cornerRadius(3)
        }
        .chartLegend(.visible)
    }
}

private extension OpenClientVisualChartPayload {
    var summary: String {
        let points = pointCount == 1 ? "1 point" : "\(pointCount) points"
        return "\(chartType.displayName) · \(points)"
    }

    func cartesianData<X: Plottable & Hashable>(
        transform: (OpenClientVisualChartXValue) -> X?
    ) -> [OpenClientCartesianDatum<X>] {
        series.flatMap { series in
            series.points.compactMap { point in
                guard let x = transform(point.x) else { return nil }
                return OpenClientCartesianDatum(
                    id: OpenClientCartesianDatum<X>.ID(
                        seriesID: series.id,
                        pointID: point.id
                    ),
                    seriesID: series.id,
                    seriesName: series.name,
                    x: x,
                    y: point.y
                )
            }
        }
    }
}

private extension OpenClientVisualChartType {
    var displayName: String {
        switch self {
        case .line: "Line chart"
        case .area: "Area chart"
        case .bar: "Bar chart"
        case .scatter: "Scatter plot"
        case .pie: "Pie chart"
        case .donut: "Donut chart"
        }
    }
}
