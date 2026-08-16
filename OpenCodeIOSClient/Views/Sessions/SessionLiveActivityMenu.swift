import SwiftUI

struct SessionLiveActivityMenu: View {
    @ObservedObject var facade: ProjectFacade

    var body: some View {
        Menu {
            Section {
                Text("Auto-start Live Activity for this project.")

                Button {
                    facade.setLiveActivityAutoStartEnabled(!facade.settingsSnapshot.isLiveActivityAutoStartEnabled)
                } label: {
                    Label(
                        autoStartActionTitle,
                        systemImage: facade.settingsSnapshot.isLiveActivityAutoStartEnabled ? "bolt.slash" : "bolt.badge.a"
                    )
                }
            }
        } label: {
            Image(systemName: toolbarSymbolName)
        }
        .accessibilityLabel("Live Activity Settings")
    }

    private var toolbarSymbolName: String {
        facade.settingsSnapshot.isLiveActivityAutoStartEnabled ? "bolt.badge.a" : "waveform.badge.plus"
    }

    private var autoStartActionTitle: LocalizedStringResource {
        facade.settingsSnapshot.isLiveActivityAutoStartEnabled ? "Disable Auto-Start" : "Enable Auto-Start"
    }
}
