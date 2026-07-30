import SwiftUI

struct OpenClientBridgeToolbarButton: View {
    @ObservedObject var bridge: OpenClientBridgeFacade
    let action: () -> Void

    var body: some View {
        let snapshot = bridge.snapshot
        if snapshot.showsToolbarButton {
            Button(action: action) {
                Image(systemName: snapshot.toolbarSystemImage)
                    .foregroundStyle(.green)
            }
            .accessibilityLabel("OpenClient Plugin: Connected")
            .accessibilityIdentifier("projects.bridge.status")
        }
    }
}

struct OpenClientBridgeStatusView: View {
    @ObservedObject var bridge: OpenClientBridgeFacade
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let snapshot = bridge.snapshot
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("OpenClient Plugin")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            HStack(spacing: 14) {
                Image(systemName: snapshot.isConnected ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 34))
                    .foregroundStyle(snapshot.isConnected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.isConnected ? "Connected" : snapshot.statusTitle)
                        .font(.title3.weight(.semibold))
                    Text(snapshot.isConnected ? "Plugin tools are ready in OpenCode." : "OpenClient will reconnect automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .accessibilityIdentifier("projects.bridge.compact-status")
#if os(iOS)
        .presentationDetents([.height(190)])
        .presentationDragIndicator(.visible)
#endif
    }
}

struct OpenClientBridgeDiagnosticsView: View {
    @ObservedObject var bridge: OpenClientBridgeFacade

    var body: some View {
        let snapshot = bridge.snapshot
        List {
            OpenClientBridgeDiagnosticsConnectionSection(snapshot: snapshot)
            OpenClientBridgeDeviceSection(snapshot: snapshot)

            if let errorMessage = snapshot.errorMessage {
                Section("Last Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button {
                    bridge.forceConnect()
                } label: {
                    Label(
                        snapshot.isConnected ? "Reconnect Now" : "Force Connect",
                        systemImage: "arrow.clockwise"
                    )
                }
                .accessibilityIdentifier("plugins.openclient.force-connect")
            } footer: {
                Text("OpenClient scans the connected OpenCode host on ports 4070 through 4090. The network is expected to be protected by your Tailnet, VPN, or firewall.")
            }
        }
        .navigationTitle("OpenClient Diagnostics")
        .opencodeInlineNavigationTitle()
        .accessibilityIdentifier("plugins.openclient.diagnostics")
    }
}

private struct OpenClientBridgeDiagnosticsConnectionSection: View {
    let snapshot: OpenClientBridgeSnapshot

    var body: some View {
        Section("Connection") {
            HStack(spacing: 12) {
                Text("Status")
                Spacer()
                Label(snapshot.statusTitle, systemImage: snapshot.toolbarSystemImage)
                    .foregroundStyle(snapshot.isConnected ? .green : .secondary)
            }

            Text(snapshot.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let endpoint = snapshot.endpoint {
                LabeledContent("Endpoint") {
                    Text(endpoint.absoluteString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if snapshot.isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connection attempt in progress")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct OpenClientBridgeDeviceSection: View {
    let snapshot: OpenClientBridgeSnapshot

    var body: some View {
        Section("This Device") {
            LabeledContent("Name", value: snapshot.displayName)
            LabeledContent("App Version", value: snapshot.appVersion)
            LabeledContent("Client ID") {
                Text(snapshot.clientID)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}
