import Foundation

struct OpenClientShareDeepLink: Equatable, Sendable {
    let payloadID: String
    let serverID: String?

    init?(url: URL) {
        guard url.scheme == "openclient", url.host() == "share",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payloadID = components.queryItems?.first(where: { $0.name == "id" })?.value,
              !payloadID.isEmpty else {
            return nil
        }
        self.payloadID = payloadID
        self.serverID = components.queryItems?.first(where: { $0.name == "server" })?.value
    }
}

extension AppViewModel {
    func prepareOpenURLPresentation(_ url: URL) {
        if let shareRequest = OpenClientShareDeepLink(url: url),
           let initialContent = shareInitialContent(payloadID: shareRequest.payloadID, deletesAfterLoad: false) {
            presentNewProjectChatSheet(
                initialContent: initialContent,
                presentsAboveConnection: true
            )
            return
        }

        guard let widgetRequest = OpenCodeWidgetDeepLink.request(from: url),
              case .newSession = widgetRequest.kind else { return }

        presentWidgetNewSessionSheet(
            for: widgetRequest,
            composerSelection: widgetComposerSelection(from: widgetRequest)
        )
    }

    func handleOpenURL(_ url: URL) async {
        if let shareRequest = OpenClientShareDeepLink(url: url) {
            await handleShareDeepLink(shareRequest)
            return
        }

        if let widgetRequest = OpenCodeWidgetDeepLink.request(from: url) {
            await handleWidgetDeepLink(widgetRequest)
            return
        }

        await handleLiveActivityURL(url)
    }

    private func handleShareDeepLink(_ request: OpenClientShareDeepLink) async {
        let initialContent = shareInitialContent(payloadID: request.payloadID, deletesAfterLoad: true)
        if let serverID = request.serverID,
           config.recentServerID != serverID {
            guard let serverConfig = recentServerConfigs.first(where: { $0.recentServerID == serverID }) else {
                errorMessage = "Open the app once before sharing to this connection."
                return
            }
            await connect(to: serverConfig)
        } else if !isConnected, hasSavedServer {
            await connect()
        }

        guard isConnected else { return }
        if projects.isEmpty {
            do {
                try await refreshProjects()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        presentNewProjectChatSheet(
            initialContent: initialContent,
            presentsAboveConnection: true
        )
    }

    private func shareInitialContent(payloadID: String, deletesAfterLoad: Bool) -> NewProjectChatInitialContent? {
        guard let payload = try? OpenClientSharePayloadStore.load(id: payloadID, deletesAfterLoad: deletesAfterLoad) else {
            return nil
        }
        let attachments = payload.attachments.map { attachment in
            OpenCodeComposerAttachment(
                id: OpenCodeIdentifier.part(),
                kind: attachment.mime.lowercased().hasPrefix("image/") ? .image : .file,
                filename: attachment.filename,
                mime: attachment.mime,
                dataURL: attachment.dataURL
            )
        }
        return NewProjectChatInitialContent(text: payload.text, attachments: attachments)
    }

    private func handleWidgetDeepLink(_ request: OpenCodeWidgetDeepLink.Request) async {
        let selection = widgetComposerSelection(from: request)
        if case .newSession = request.kind {
            presentWidgetNewSessionSheet(for: request, composerSelection: selection)
        }

        guard await ensureWidgetDeepLinkServerConnection(serverID: request.serverID) else { return }

        do {
            if projects.isEmpty || shouldRefreshProjects(for: request) {
                try await refreshProjects()
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let project = resolveWidgetDeepLinkProject(request) else {
            errorMessage = "Project is no longer available. Open the app to sync widget settings."
            return
        }

        await loadComposerOptions()

        switch request.kind {
        case .newSession:
            return
        case let .action(commandName):
            await startWidgetSession(project: project, directory: request.directory, commandName: commandName, composerSelection: selection)
        }
    }

    private func presentWidgetNewSessionSheet(
        for request: OpenCodeWidgetDeepLink.Request,
        composerSelection: NewProjectChatComposerSelection?
    ) {
        if let existing = newProjectChatSheetRequest,
           existing.presentsAboveConnection,
           existing.projectID == request.projectID,
           existing.workspaceDirectory == request.directory,
           existing.locksProject,
           existing.composerSelection == composerSelection {
            return
        }

        presentNewProjectChatSheet(
            projectID: request.projectID,
            workspaceDirectory: request.directory,
            locksProject: true,
            composerSelection: composerSelection,
            presentsAboveConnection: true
        )
    }

    private func shouldRefreshProjects(for request: OpenCodeWidgetDeepLink.Request) -> Bool {
        if let projectID = request.projectID,
           !projects.contains(where: { $0.id == projectID }) {
            return true
        }
        return false
    }

    private func ensureWidgetDeepLinkServerConnection(serverID: String?) async -> Bool {
        if let serverID, config.recentServerID != serverID {
            guard let serverConfig = recentServerConfigs.first(where: { $0.recentServerID == serverID }) else {
                errorMessage = "Open the app to reconnect the server used by this widget."
                return false
            }
            await connect(to: serverConfig)
            return isConnected
        }

        if !isConnected {
            guard hasSavedServer else { return false }
            await connect()
        }
        return isConnected
    }

    private func resolveWidgetDeepLinkProject(_ request: OpenCodeWidgetDeepLink.Request) -> OpenCodeProject? {
        if let projectID = request.projectID,
           let project = projects.first(where: { $0.id == projectID }) {
            return project
        }

        if let directory = request.directory {
            let key = workspaceKey(directory)
            if let project = projects.first(where: { project in
                project.id != "global" && (
                    workspaceKey(project.worktree) == key ||
                        (project.sandboxes ?? []).contains { workspaceKey($0) == key }
                )
            }) {
                return project
            }
        }

        if let currentProject {
            return currentProject
        }

        return projects.first(where: { $0.id != "global" }) ?? projects.first
    }

    private func widgetComposerSelection(from request: OpenCodeWidgetDeepLink.Request) -> NewProjectChatComposerSelection? {
        let modelReference: OpenCodeModelReference?
        if let providerID = request.providerID, let modelID = request.modelID {
            modelReference = OpenCodeModelReference(providerID: providerID, modelID: modelID)
        } else {
            modelReference = nil
        }

        guard modelReference != nil || request.reasoningVariant != nil else { return nil }
        return NewProjectChatComposerSelection(
            agentName: nil,
            modelReference: modelReference,
            reasoningVariant: request.reasoningVariant
        )
    }

    @discardableResult
    private func startWidgetSession(
        project: OpenCodeProject,
        directory: String?,
        commandName: String?,
        composerSelection: NewProjectChatComposerSelection?
    ) async -> Bool {
        guard backendMode == .server, isConnected else {
            errorMessage = "Connect to an OpenCode server before starting a session."
            return false
        }
        guard canCreateSessionOrPresentPaywall() else { return false }

        let hasCommand = commandName?.isEmpty == false
        var didReservePrompt = false
        if hasCommand {
            guard reserveUserPromptIfAllowed() else { return false }
            didReservePrompt = true
        }

        let routeDirectory = project.id == "global" ? nil : project.worktree
        let targetDirectory: String?
        if project.id == "global" {
            targetDirectory = nil
        } else if let directory, !directory.isEmpty {
            targetDirectory = directory
        } else {
            targetDirectory = project.worktree
        }

        isLoading = true
        defer { isLoading = false }

        do {
            currentProject = project
            prepareDirectorySelection(routeDirectory)

            let createSubmission = sessionCoordinator.prepareCreateSession(title: "", directory: targetDirectory)
            let session = try await sessionCoordinator.submitCreate(client: client, submission: createSubmission)
            recordCreatedSessionForMetering()
            upsertVisibleSession(session)
            try await reloadSessions()
            await loadComposerOptions()

            if let composerSelection {
                applyNewProjectChatComposerSelection(composerSelection, to: session)
            } else {
                seedComposerSelectionsForNewSession(session)
            }

            upsertVisibleSession(session)
            prepareSessionSelection(session)
            await selectSession(session)

            if let commandName, !commandName.isEmpty {
                try await submitWidgetCommand(named: commandName, in: session)
            }

            errorMessage = nil
            return true
        } catch {
            if didReservePrompt {
                refundReservedUserPromptIfNeeded()
            }
            isLoadingSessions = false
            appendDebugLog("widget deep link error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func submitWidgetCommand(named commandName: String, in session: OpenCodeSession) async throws {
        let command = directoryCommands.first { $0.name == commandName } ?? OpenCodeCommand(
            name: commandName,
            description: nil,
            agent: nil,
            model: nil,
            source: "command",
            template: "",
            subtask: nil,
            hints: []
        )
        let modelReference = effectiveModelReference(for: session)
        let agentName = effectiveAgentName(for: session)
        let variant = selectedVariant(for: session)
        let commandPreparation = sessionCoordinator.prepareCommandSubmission(
            command: command,
            arguments: "",
            attachments: [],
            session: session,
            selectedDirectory: effectiveSelectedDirectory,
            currentProjectID: currentProject?.id,
            model: modelReference,
            agent: agentName,
            variant: variant
        )
        let previousStatus = sessionStatuses[session.id]
        let statusTransition = sessionCoordinator.commandStatusTransition(
            for: commandPreparation,
            previousStatus: previousStatus
        )
        sessionStatuses[statusTransition.sessionID] = statusTransition.nextStatus
        await maybeAutoStartLiveActivity(for: session)

        do {
            try await sessionCoordinator.submitCommand(client: client, submission: commandPreparation.submission)
            appendDebugLog("widget command accepted session=\(debugSessionLabel(session)) command=\(command.name)")
        } catch {
            sessionStatuses[statusTransition.sessionID] = statusTransition.previousStatus
            throw error
        }
    }
}
