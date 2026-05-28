import Combine
import Foundation

@MainActor
final class FunAndGamesStore: ObservableObject {
    @Published var preferences: FunAndGamesPreferences
    @Published var findPlaceSessionsByID: [String: FindPlaceGameSession]
    @Published var findBugSessionsByID: [String: FindBugGameSession]
    @Published var pendingFindBugLanguage: FindBugGameLanguage?

    init(
        preferences: FunAndGamesPreferences = FunAndGamesPreferences(),
        findPlaceSessionsByID: [String: FindPlaceGameSession] = [:],
        findBugSessionsByID: [String: FindBugGameSession] = [:],
        pendingFindBugLanguage: FindBugGameLanguage? = nil
    ) {
        self.preferences = preferences
        self.findPlaceSessionsByID = findPlaceSessionsByID
        self.findBugSessionsByID = findBugSessionsByID
        self.pendingFindBugLanguage = pendingFindBugLanguage
    }

    func findPlaceGame(for sessionID: String) -> FindPlaceGameSession? {
        findPlaceSessionsByID[sessionID]
    }

    func findBugGame(for sessionID: String) -> FindBugGameSession? {
        findBugSessionsByID[sessionID]
    }

    @discardableResult
    func recordFindPlaceSession(_ session: FindPlaceGameSession) -> Bool {
        guard findPlaceSessionsByID[session.sessionID] != session else { return false }
        var next = findPlaceSessionsByID
        next[session.sessionID] = session
        findPlaceSessionsByID = next
        return true
    }

    @discardableResult
    func recordFindBugSession(_ session: FindBugGameSession) -> Bool {
        guard findBugSessionsByID[session.sessionID] != session else { return false }
        var next = findBugSessionsByID
        next[session.sessionID] = session
        findBugSessionsByID = next
        return true
    }

    @discardableResult
    func inferGames(from messages: [OpenCodeMessageEnvelope], forSessionID sessionID: String) -> Bool {
        var changed = false

        if findPlaceSessionsByID[sessionID] == nil,
           let game = Self.inferredFindPlaceGame(in: messages, sessionID: sessionID) {
            changed = recordFindPlaceSession(game) || changed
        }

        if findBugSessionsByID[sessionID] == nil,
           let game = Self.inferredFindBugGame(in: messages, sessionID: sessionID) {
            changed = recordFindBugSession(game) || changed
        }

        return changed
    }

    @discardableResult
    func inferGame(from part: OpenCodePart) -> Bool {
        guard let sessionID = part.sessionID,
              let text = part.text else { return false }
        return inferGame(fromSetupText: text, sessionID: sessionID)
    }

    @discardableResult
    func inferGame(from event: OpenCodeTypedEvent) -> Bool {
        guard case let .messagePartUpdated(part) = event else { return false }
        return inferGame(from: part)
    }

    @discardableResult
    private func inferGame(fromSetupText text: String, sessionID: String) -> Bool {
        var changed = false

        if findPlaceSessionsByID[sessionID] == nil,
           text.contains(FindPlaceGame.setupMarker),
           let city = Self.findPlaceCity(fromSetupPrompt: text) {
            changed = recordFindPlaceSession(
                FindPlaceGameSession(
                    sessionID: sessionID,
                    city: city,
                    weather: Self.findPlaceWeather(fromSetupPrompt: text)
                )
            ) || changed
        }

        if findBugSessionsByID[sessionID] == nil,
           text.contains(FindBugGame.setupMarker),
           let language = Self.findBugLanguage(fromSetupPrompt: text) {
            changed = recordFindBugSession(FindBugGameSession(sessionID: sessionID, language: language)) || changed
        }

        return changed
    }

    static func inferredFindPlaceGame(in messages: [OpenCodeMessageEnvelope], sessionID: String) -> FindPlaceGameSession? {
        for message in messages where message.info.sessionID == nil || message.info.sessionID == sessionID {
            for part in message.parts {
                guard let text = part.text, text.contains(FindPlaceGame.setupMarker) else { continue }
                guard let city = findPlaceCity(fromSetupPrompt: text) else { continue }
                return FindPlaceGameSession(sessionID: sessionID, city: city, weather: findPlaceWeather(fromSetupPrompt: text))
            }
        }

        return nil
    }

    static func inferredFindBugGame(in messages: [OpenCodeMessageEnvelope], sessionID: String) -> FindBugGameSession? {
        for message in messages where message.info.sessionID == nil || message.info.sessionID == sessionID {
            for part in message.parts {
                guard let text = part.text, text.contains(FindBugGame.setupMarker) else { continue }
                guard let language = findBugLanguage(fromSetupPrompt: text) else { continue }
                return FindBugGameSession(sessionID: sessionID, language: language)
            }
        }

        return nil
    }

    private static func findBugLanguage(fromSetupPrompt text: String) -> FindBugGameLanguage? {
        let lines = text.components(separatedBy: .newlines)
        guard let languageLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Markdown fence language:") }) else {
            return nil
        }
        let id = languageLine
            .replacingOccurrences(of: "Markdown fence language:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FindBugGame.supportedLanguages.first { $0.id == id } ?? FindBugGameLanguage(id: id, title: id.capitalized)
    }

    private static func findPlaceCity(fromSetupPrompt text: String) -> FindPlaceGameCity? {
        let lines = text.components(separatedBy: .newlines)
        let cityLine = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Secret city:") }
        let coordinatesLine = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Coordinates:") }

        guard let cityLine, let coordinatesLine else { return nil }

        let cityValue = cityLine
            .replacingOccurrences(of: "Secret city:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cityParts = cityValue.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cityParts.count == 2 else { return nil }

        let coordinateValue = coordinatesLine
            .replacingOccurrences(of: "Coordinates:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinateParts = coordinateValue.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard coordinateParts.count == 2,
              let latitude = Double(coordinateParts[0]),
              let longitude = Double(coordinateParts[1]) else {
            return nil
        }

        return FindPlaceGameCity(name: cityParts[0], country: cityParts[1], latitude: latitude, longitude: longitude)
    }

    private static func findPlaceWeather(fromSetupPrompt text: String) -> FindPlaceWeatherSummary? {
        let lines = text.components(separatedBy: .newlines)
        guard let clueLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Current clue:") }) else {
            return nil
        }

        let clue = clueLine
            .replacingOccurrences(of: "Current clue:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnosticLine = lines.first { $0.contains("WeatherKit diagnostic:") }
        let diagnostic = diagnosticLine?
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "WeatherKit diagnostic:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorDescription = diagnostic == "success" ? nil : diagnostic
        let provider = errorDescription == nil && !clue.hasPrefix("Location clue:") ? "WeatherKit" : "Fallback"
        return FindPlaceWeatherSummary(text: clue, provider: provider, errorDescription: errorDescription)
    }
}
