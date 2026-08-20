import Foundation
import XCTest

final class LocalizationCatalogTests: XCTestCase {
    private let requiredLanguages = ["pt-BR", "it"]
    private let catalogPaths = [
        "OpenCodeIOSClient/Localizable.xcstrings",
        "OpenCodeIOSClient/AppShortcuts.xcstrings",
        "OpenCodeIOSClient/InfoPlist.xcstrings",
        "OpenCodeChatActivityExtension/Localizable.xcstrings",
        "OpenCodeChatActivityExtension/InfoPlist.xcstrings",
        "OpenCodeShareExtension/Localizable.xcstrings",
        "OpenCodeShareExtension/InfoPlist.xcstrings",
    ]

    func testRequiredLanguageCatalogsAreComplete() throws {
        for path in catalogPaths {
            let strings = try catalogStrings(at: path)
            XCTAssertFalse(strings.isEmpty, "Expected localization entries in \(path)")

            for (key, value) in strings {
                let entry = try XCTUnwrap(value as? [String: Any], "Invalid entry for \(key) in \(path)")
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "Missing localizations for \(key) in \(path)")
                for language in requiredLanguages {
                    let localization = try XCTUnwrap(
                        localizations[language] as? [String: Any],
                        "Missing \(language) translation for \(key) in \(path)"
                    )
                    XCTAssertTrue(isTranslated(localization), "Incomplete \(language) translation for \(key) in \(path)")
                }
            }
        }
    }

    func testRequiredLanguageTranslationsPreservePlaceholders() throws {
        for path in catalogPaths {
            let strings = try catalogStrings(at: path)

            for (key, value) in strings {
                let entry = try XCTUnwrap(value as? [String: Any])
                let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
                let english = localizations["en"] as? [String: Any]
                let sourceValues = localizedValues(english, fallback: key)

                for language in requiredLanguages {
                    let localization = try XCTUnwrap(localizations[language] as? [String: Any])
                    let translatedValues = localizedValues(localization, fallback: key)

                    XCTAssertEqual(sourceValues.count, translatedValues.count, "Value count differs for \(key) in \(path) [\(language)]")
                    for (source, translation) in zip(sourceValues, translatedValues) {
                        XCTAssertEqual(
                            placeholders(in: source),
                            placeholders(in: translation),
                            "Placeholders differ for \(key) in \(path) [\(language)]"
                        )
                    }
                }
            }
        }
    }

    func testMainAppEnablesMultipleScenes() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryURL.appendingPathComponent("OpenCodeIOSClient/Generated-Info.plist")
        )
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let sceneManifest = try XCTUnwrap(info["UIApplicationSceneManifest"] as? [String: Any])

        XCTAssertEqual(sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool, true)
    }

    private func catalogStrings(at path: String) throws -> [String: Any] {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryURL.appendingPathComponent(path))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    private func isTranslated(_ localization: [String: Any]) -> Bool {
        if let stringUnit = localization["stringUnit"] as? [String: Any] {
            return stringUnit["state"] as? String == "translated"
        }
        if let stringSet = localization["stringSet"] as? [String: Any] {
            return stringSet["state"] as? String == "translated"
        }
        return false
    }

    private func localizedValues(_ localization: [String: Any]?, fallback: String) -> [String] {
        if let stringUnit = localization?["stringUnit"] as? [String: Any],
           let value = stringUnit["value"] as? String {
            return [value]
        }
        if let stringSet = localization?["stringSet"] as? [String: Any],
           let values = stringSet["values"] as? [String] {
            return values
        }
        return [fallback]
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:lld|ld|lf|d|f|@|%)|\$\{applicationName\}"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value) else { return nil }
            return String(value[matchRange]).replacingOccurrences(
                of: #"^%\d+\$"#,
                with: "%",
                options: .regularExpression
            )
        }.sorted()
    }
}
