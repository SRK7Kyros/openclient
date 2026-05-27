import SwiftUI

struct CreateSessionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var startingSnapshot: NewSessionStartingSnapshot?

    var body: some View {
        NavigationStack {
            Group {
                if let startingSnapshot {
                    NewSessionStartingPreview(snapshot: startingSnapshot)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(OpenCodePlatformColor.groupedBackground)
                } else {
                    createSessionForm
                }
            }
            .navigationTitle("New Session")
            .opencodeInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .opencodeLeading) {
                    Button("Cancel") {
                        viewModel.isShowingCreateSessionSheet = false
                    }
                    .disabled(startingSnapshot != nil)
                }
            }
        }
        .presentationDetents(viewModel.hasProUnlock && !showsWorkspacePicker ? [.medium] : [.large])
    }

    private var createSessionForm: some View {
        Form {
            Section("Session Name") {
                TextField("Optional title", text: $viewModel.draftTitle)
                    .accessibilityIdentifier("sessions.create.title")
            }

            Section("Scope") {
                Text(viewModel.projectScopeTitle)
                    .foregroundStyle(.secondary)
            }

            if showsWorkspacePicker {
                Section("Workspace") {
                    Picker("Workspace", selection: $viewModel.newSessionWorkspaceSelection) {
                        Text(viewModel.newSessionWorkspaceTitle(for: .main))
                            .tag(NewSessionWorkspaceSelection.main)

                        ForEach(workspaceDirectories, id: \.self) { directory in
                            if directory != viewModel.currentProject?.worktree {
                                Text(viewModel.newSessionWorkspaceTitle(for: .directory(directory)))
                                    .tag(NewSessionWorkspaceSelection.directory(directory))
                            }
                        }

                        Text("Create new worktree")
                            .tag(NewSessionWorkspaceSelection.createNew)
                    }

                    if viewModel.newSessionWorkspaceSelection == .createNew {
                        TextField("Worktree name (optional)", text: $viewModel.newWorkspaceName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("sessions.create.worktree.name")

                        Text("OpenCode will create a separate git worktree, then start this session inside it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(selectedWorkspaceDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.hasProUnlock {
                Section("Free Plan") {
                    Text(viewModel.canCreateFreeSession ? "Your first session is included. Upgrade for unlimited sessions and prompts." : "Upgrade to create more sessions.")
                        .foregroundStyle(.secondary)

                    Button("Upgrade to Pro") {
                        viewModel.isShowingCreateSessionSheet = false
                        viewModel.presentPaywall(reason: .sessionLimit)
                    }
                }
            }

            Section {
                Button(createButtonTitle) {
                    startCreatingSession()
                }
                .disabled(viewModel.isLoading)
                .accessibilityIdentifier("sessions.create.confirm")
            }
        }
    }

    private var showsWorkspacePicker: Bool {
        viewModel.isProjectWorkspacesEnabled && viewModel.hasGitProject
    }

    private var workspaceDirectories: [String] {
        viewModel.workspaceDirectories()
    }

    private var selectedWorkspaceDescription: String {
        switch viewModel.newSessionWorkspaceSelection {
        case .main:
            return viewModel.currentProject?.worktree ?? viewModel.projectScopeTitle
        case let .directory(directory):
            return directory
        case .createNew:
            return ""
        }
    }

    private var createButtonTitle: String {
        if viewModel.isLoading, viewModel.newSessionWorkspaceSelection == .createNew {
            return "Creating Worktree..."
        }

        return viewModel.isLoading ? "Creating..." : "Create Session"
    }

    private func startCreatingSession() {
        startingSnapshot = NewSessionStartingSnapshot(
            title: submittedTitle,
            subtitle: viewModel.projectScopeTitle,
            promptPreview: nil,
            attachmentCount: 0,
            phase: viewModel.newSessionWorkspaceSelection == .createNew ? .creatingWorktree : .creatingSession
        )

        Task { @MainActor in
            await viewModel.createSession()
            if viewModel.isShowingCreateSessionSheet {
                startingSnapshot = nil
            }
        }
    }

    private var submittedTitle: String {
        let title = viewModel.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "New Session" : title
    }
}

enum NewSessionStartingPhase: Equatable {
    case creatingWorktree
    case creatingSession
    case sendingMessage
    case waitingForOpenCode

    var title: String {
        switch self {
        case .creatingWorktree:
            return "Creating worktree"
        case .creatingSession:
            return "Creating session"
        case .sendingMessage:
            return "Sending message"
        case .waitingForOpenCode:
            return "Waiting for OpenCode"
        }
    }

    var detail: String {
        switch self {
        case .creatingWorktree:
            return "Preparing a fresh workspace before the session opens."
        case .creatingSession:
            return "Setting up the session before opening chat."
        case .sendingMessage:
            return "Your first message is being added to the new session."
        case .waitingForOpenCode:
            return "OpenCode accepted the prompt. Chat will open with this message already in place."
        }
    }
}

struct NewSessionStartingSnapshot: Equatable {
    var title: String
    var subtitle: String
    var promptPreview: String?
    var attachmentCount: Int
    var phase: NewSessionStartingPhase
}

struct NewSessionStartingPreview: View {
    let snapshot: NewSessionStartingSnapshot

    @State private var hasPresentedUserBubble = false

    var body: some View {
        Group {
            if showsChatPreview {
                chatLikePreview
            } else {
                sessionOnlyPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard showsChatPreview else { return }
            hasPresentedUserBubble = false
            withAnimation(.snappy(duration: 0.42, extraBounce: 0.04)) {
                hasPresentedUserBubble = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessions.create.startingPreview")
    }

    private var showsChatPreview: Bool {
        guard let promptPreview = snapshot.promptPreview else { return snapshot.attachmentCount > 0 }
        return !promptPreview.isEmpty || snapshot.attachmentCount > 0
    }

    private var chatLikePreview: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                pendingUserBubble(text: snapshot.promptPreview ?? "")
                    .offset(y: hasPresentedUserBubble ? 0 : 220)
                    .opacity(hasPresentedUserBubble ? 1 : 0.78)
                    .scaleEffect(hasPresentedUserBubble ? 1 : 0.96, anchor: .bottomTrailing)

                ThinkingRow(animateEntry: true)
                    .padding(.top, 2)
                    .opacity(hasPresentedUserBubble ? 1 : 0)
            }
            .frame(maxWidth: 430)
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
    }

    private var sessionOnlyPreview: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text(snapshot.phase.title)
                    .font(.title3.weight(.semibold))

                Text(snapshot.phase.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            ThinkingRow(animateEntry: true)
                .frame(maxWidth: 430)

            Spacer(minLength: 0)
        }
    }

    private func pendingUserBubble(text: String) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 44)

            VStack(alignment: .trailing, spacing: 8) {
                if !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if snapshot.attachmentCount > 0 {
                    Label(attachmentLabel, systemImage: "paperclip")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var attachmentLabel: String {
        snapshot.attachmentCount == 1 ? "1 attachment" : "\(snapshot.attachmentCount) attachments"
    }
}
