import SwiftUI

struct CreateProjectSheet: View {
    @ObservedObject var facade: ProjectFacade

    var body: some View {
        let snapshot = facade.createProjectSnapshot

        NavigationStack {
            List {
                Section("Directory") {
                    TextField("Search under \(snapshot.defaultSearchRoot)", text: Binding(
                        get: { facade.createProjectQuery },
                        set: { facade.createProjectQuery = $0 }
                    ))
                        .opencodeDisableTextAutocapitalization()
                        .autocorrectionDisabled()
                        .onChange(of: facade.createProjectQuery) { _, _ in
                            Task { await facade.searchCreateProjectDirectories() }
                        }
                }

                if let selectedDirectory = snapshot.selectedDirectory {
                    Section("Selected Directory") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                Task { await facade.createProject(from: selectedDirectory) }
                            } label: {
                                ProjectRow(
                                    title: facade.createProjectResultPath(selectedDirectory).split(separator: "/").last.map(String.init) ?? selectedDirectory,
                                    subtitle: facade.createProjectResultPath(selectedDirectory),
                                    systemImage: "folder.badge.plus",
                                    isSelected: true
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(snapshot.isLoading)

                            Button {
                                Task { await facade.createProject(from: selectedDirectory) }
                            } label: {
                                Text(snapshot.isLoading ? LocalizedStringResource("Selecting...") : LocalizedStringResource("Select"))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(snapshot.isLoading)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Directories") {
                    if snapshot.results.isEmpty {
                        Text("No directories found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.results, id: \.self) { directory in
                            Button {
                                Task { await facade.selectCreateProjectDirectory(directory) }
                            } label: {
                                let displayPath = facade.createProjectResultPath(directory)
                                ProjectRow(
                                    title: displayPath.split(separator: "/").last.map(String.init) ?? displayPath,
                                    subtitle: displayPath,
                                    systemImage: "folder.badge.plus",
                                    isSelected: snapshot.selectedDirectory == directory
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(snapshot.isLoading)
                        }
                    }
                }
            }
            .navigationTitle("Create Project")
            .opencodeInlineNavigationTitle()
            .onAppear {
                if snapshot.results.isEmpty {
                    Task { await facade.searchCreateProjectDirectories() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") {
                        facade.dismissCreateProject()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
