import MapKit
import SwiftUI

struct OpenClientVisualMapActivity: Equatable {
    let payload: OpenClientVisualMapPayload
    let status: String
    let errorMessage: String?

    init?(part: OpenCodePart) {
        guard part.type == "tool",
              part.tool == "openclient_execute_tool",
              let state = part.state,
              state.input?.toolID == OpenClientVisualMapContract.toolID else {
            return nil
        }

        let payloadValue: OpenCodeJSONValue?
        if state.metadata?.renderer == OpenClientVisualMapContract.rendererID {
            payloadValue = state.metadata?.payload
        } else if let arguments = state.input?.arguments {
            payloadValue = .object(arguments)
        } else {
            payloadValue = nil
        }
        guard let payloadValue,
              let data = try? JSONEncoder().encode(payloadValue),
              let decoded = try? JSONDecoder().decode(OpenClientVisualMapPayload.self, from: data),
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

struct OpenClientVisualMapView: View {
    let activity: OpenClientVisualMapActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OpenClientVisualMapHeader(
                title: activity.payload.title ?? "Map",
                markerCount: activity.payload.markers.count,
                isRunning: activity.isRunning
            )
            .padding(12)

            Map(
                initialPosition: .region(activity.payload.coordinateRegion),
                interactionModes: [.pan, .zoom]
            ) {
                if activity.payload.markers.isEmpty {
                    Marker(
                        activity.payload.title ?? "Location",
                        coordinate: activity.payload.center.clLocationCoordinate
                    )
                } else {
                    ForEach(activity.payload.markers) { marker in
                        Marker(marker.title, coordinate: marker.coordinate.clLocationCoordinate)
                    }
                }
            }
            .id(activity.payload)
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 220)
            .accessibilityIdentifier("chat.tool.visual-map")

            if !activity.payload.markers.isEmpty {
                OpenClientVisualMapMarkerSummary(markers: activity.payload.markers)
                    .padding(12)
            }

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

private struct OpenClientVisualMapMarkerSummary: View {
    let markers: [OpenClientVisualMapMarker]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(markers.prefix(3)) { marker in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(marker.title)
                            .font(.caption.weight(.semibold))
                        if let subtitle = marker.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if markers.count > 3 {
                Text("\(markers.count - 3) more markers")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OpenClientVisualMapHeader: View {
    let title: String
    let markerCount: Int
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "map.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(markerCount == 1 ? "1 marker" : "\(markerCount) markers")
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

private extension OpenClientVisualMapPayload {
    var coordinateRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clLocationCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: span.latitudeDelta,
                longitudeDelta: span.longitudeDelta
            )
        )
    }
}

private extension OpenClientVisualMapCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
