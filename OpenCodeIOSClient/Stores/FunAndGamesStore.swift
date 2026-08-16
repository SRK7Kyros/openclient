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
        let languagePrefixes = [FindBugGame.languageIDPrefix, "Markdown fence language:"]
        guard let languageLine = lines.first(where: { line in
            languagePrefixes.contains { line.contains($0) }
        }), let prefix = languagePrefixes.first(where: { languageLine.contains($0) }) else {
            return nil
        }
        let id = languageLine
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FindBugGame.supportedLanguages.first { $0.id == id } ?? FindBugGameLanguage(id: id, title: id.capitalized)
    }

    private static func findPlaceCity(fromSetupPrompt text: String) -> FindPlaceGameCity? {
        let lines = text.components(separatedBy: .newlines)
        let cityPrefixes = [FindPlaceGame.secretCityPrefix, "Secret city:"]
        let coordinatePrefixes = [FindPlaceGame.coordinatesPrefix, "Coordinates:"]
        let cityLine = lines.first { line in cityPrefixes.contains { line.contains($0) } }
        let coordinatesLine = lines.first { line in coordinatePrefixes.contains { line.contains($0) } }

        guard let cityLine, let coordinatesLine,
              let cityPrefix = cityPrefixes.first(where: { cityLine.contains($0) }),
              let coordinatePrefix = coordinatePrefixes.first(where: { coordinatesLine.contains($0) }) else { return nil }

        let cityValue = cityLine
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: cityPrefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cityParts = cityValue.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cityParts.count == 2 else { return nil }

        let coordinateValue = coordinatesLine
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: coordinatePrefix, with: "")
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
        let cluePrefixes = [FindPlaceGame.cluePrefix, "Current clue:"]
        guard let clueLine = lines.first(where: { line in cluePrefixes.contains { line.contains($0) } }),
              let cluePrefix = cluePrefixes.first(where: { clueLine.contains($0) }) else {
            return nil
        }

        let clue = clueLine
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: cluePrefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnosticPrefixes = [FindPlaceGame.weatherDiagnosticPrefix, "WeatherKit diagnostic:"]
        let diagnosticLine = lines.first { line in diagnosticPrefixes.contains { line.contains($0) } }
        let diagnosticPrefix = diagnosticLine.flatMap { line in diagnosticPrefixes.first { line.contains($0) } }
        let diagnostic = diagnosticLine?
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: diagnosticPrefix ?? "", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errorDescription = diagnostic == "success" ? nil : diagnostic
        let provider = errorDescription == nil ? "WeatherKit" : "Fallback"
        return FindPlaceWeatherSummary(text: clue, provider: provider, errorDescription: errorDescription)
    }
}
