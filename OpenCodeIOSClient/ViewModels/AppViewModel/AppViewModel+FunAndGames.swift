import Foundation
import SwiftUI

extension AppViewModel {
    func presentFindPlaceModelSheet() {
        withAnimation(opencodeSelectionAnimation) {
            isShowingFindPlaceModelSheet = true
        }
    }

    func presentFindBugLanguageSheet() {
        pendingFindBugLanguage = nil
        withAnimation(opencodeSelectionAnimation) {
            isShowingFindBugLanguageSheet = true
        }
    }

    func selectFindBugLanguage(_ language: FindBugGameLanguage) {
        pendingFindBugLanguage = language
        withAnimation(opencodeSelectionAnimation) {
            isShowingFindBugLanguageSheet = false
            isShowingFindBugModelSheet = true
        }
    }

    func startFindPlaceGame(model reference: OpenCodeModelReference) async {
        isLoading = true
        defer { isLoading = false }

        let globalProject = projects.first(where: { $0.id == "global" }) ?? OpenCodeProject(
            id: "global",
            worktree: "",
            vcs: nil,
            name: "Global",
            sandboxes: nil,
            icon: nil,
            time: nil
        )

        do {
            withAnimation(opencodeSelectionAnimation) {
                currentProject = globalProject
                isShowingFindPlaceModelSheet = false
            }
            prepareDirectorySelection(nil)
            try await reloadSessions()
            await loadComposerOptions()

            let city = FindPlaceGame.randomCity()
            let weather = await FindPlaceWeatherProvider.summary(for: city)
            if let weatherError = weather.errorDescription {
                appendDebugLog("find-place WeatherKit fallback city=\(city.id) error=\(weatherError)")
            } else {
                appendDebugLog("find-place WeatherKit success city=\(city.id)")
            }
            let session = try await client.createSession(title: String(localized: "Find the Place"), directory: nil)
            upsertVisibleSession(session)
            try await reloadSessions()
            upsertVisibleSession(session)

            selectedModelsBySessionID[session.id] = reference
            funAndGamesStore.recordFindPlaceSession(FindPlaceGameSession(sessionID: session.id, city: city, weather: weather))
            withAnimation(opencodeSelectionAnimation) {
                selectedProjectContentTab = .sessions
                selectedSession = session
                isLoadingSelectedSession = true
                messages = []
                sessionInteractionStore.replaceTodos([])
            }
            restoreMessageDraft(for: session)
            streamDirectory = session.directory
            try await loadMessages(for: session)
            await sendMessage(
                FindPlaceGame.starterPrompt(city: city, weather: weather),
                in: session,
                userVisible: false,
                appendOptimisticMessage: false,
                meterPrompt: false
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startFindBugGame(model reference: OpenCodeModelReference) async {
        guard let language = pendingFindBugLanguage else { return }

        isLoading = true
        defer { isLoading = false }

        let globalProject = projects.first(where: { $0.id == "global" }) ?? OpenCodeProject(
            id: "global",
            worktree: "",
            vcs: nil,
            name: "Global",
            sandboxes: nil,
            icon: nil,
            time: nil
        )

        do {
            withAnimation(opencodeSelectionAnimation) {
                currentProject = globalProject
                isShowingFindBugModelSheet = false
            }
            prepareDirectorySelection(nil)
            try await reloadSessions()
            await loadComposerOptions()

            let session = try await client.createSession(title: String(localized: "Find the Bug"), directory: nil)
            upsertVisibleSession(session)
            try await reloadSessions()
            upsertVisibleSession(session)

            selectedModelsBySessionID[session.id] = reference
            funAndGamesStore.recordFindBugSession(FindBugGameSession(sessionID: session.id, language: language))
            pendingFindBugLanguage = nil
            withAnimation(opencodeSelectionAnimation) {
                selectedProjectContentTab = .sessions
                selectedSession = session
                isLoadingSelectedSession = true
                messages = []
                sessionInteractionStore.replaceTodos([])
            }
            restoreMessageDraft(for: session)
            streamDirectory = session.directory
            try await loadMessages(for: session)
            await sendMessage(
                FindBugGame.starterPrompt(language: language),
                in: session,
                userVisible: false,
                appendOptimisticMessage: false,
                meterPrompt: false
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func findPlaceGame(for sessionID: String) -> FindPlaceGameSession? {
        if let game = funAndGamesStore.findPlaceGame(for: sessionID) {
            return game
        }

        return FunAndGamesStore.inferredFindPlaceGame(in: gameInferenceMessages(for: sessionID), sessionID: sessionID)
    }

    func findBugGame(for sessionID: String) -> FindBugGameSession? {
        if let game = funAndGamesStore.findBugGame(for: sessionID) {
            return game
        }

        return FunAndGamesStore.inferredFindBugGame(in: gameInferenceMessages(for: sessionID), sessionID: sessionID)
    }

    func isFunAndGamesSession(_ sessionID: String) -> Bool {
        findPlaceGame(for: sessionID) != nil || findBugGame(for: sessionID) != nil
    }

    func isKnownFunAndGamesSession(_ sessionID: String) -> Bool {
        findPlaceSessionsByID[sessionID] != nil || findBugSessionsByID[sessionID] != nil
    }

    func shouldMeterPrompts(for sessionID: String) -> Bool {
        !isFunAndGamesSession(sessionID)
    }

    @discardableResult
    func inferFunAndGames(from messages: [OpenCodeMessageEnvelope], forSessionID sessionID: String) -> Bool {
        let changed = funAndGamesStore.inferGames(from: messages, forSessionID: sessionID)
        if changed {
            objectWillChange.send()
        }
        return changed
    }

    @discardableResult
    func inferFunAndGames(from event: OpenCodeTypedEvent) -> Bool {
        let changed = funAndGamesStore.inferGame(from: event)
        if changed {
            objectWillChange.send()
        }
        return changed
    }

    private func gameInferenceMessages(for sessionID: String) -> [OpenCodeMessageEnvelope] {
        if selectedSession?.id == sessionID, !messages.isEmpty {
            return messages
        }

        let syncedMessages = directoryStore.syncState.messageEnvelopes(forSessionID: sessionID)
        if !syncedMessages.isEmpty {
            return syncedMessages
        }

        if let cachedMessages = cachedMessagesBySessionID[sessionID], !cachedMessages.isEmpty {
            return cachedMessages
        }

        return messages.filter { $0.info.sessionID == sessionID }
    }
}
