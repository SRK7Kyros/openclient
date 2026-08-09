import XCTest
@testable import OpenClient

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppIconStoreTests: XCTestCase {
    func testAvailableIconsParsesPrimaryAndAlternateIcons() {
        let infoDictionary: [String: Any] = [
            "CFBundleIcons": [
                "CFBundlePrimaryIcon": [
                    "CFBundleIconName": "AppIcon",
                    "CFBundleIconFiles": ["AppIcon60x60"],
                ],
                "CFBundleAlternateIcons": [
                    "ocean-blue": [
                        "CFBundleIconName": "OceanBlue",
                        "CFBundleIconFiles": ["OceanBlue60x60"],
                    ],
                ],
            ],
            "OpenClientAlternateIconDisplayNames": [
                "ocean-blue": "Ocean",
            ],
        ]

        let icons = AppIconStore.availableIcons(in: infoDictionary)

        XCTAssertEqual(icons, [
            OpenClientAppIcon(alternateIconName: nil, displayName: "Default", iconFiles: ["AppIcon60x60"]),
            OpenClientAppIcon(alternateIconName: "ocean-blue", displayName: "Ocean", iconFiles: ["OceanBlue60x60"]),
        ])
    }

    func testAvailableIconsFormatsAlternateNameWhenNoDisplayNameIsConfigured() {
        let infoDictionary: [String: Any] = [
            "CFBundleIcons": [
                "CFBundleAlternateIcons": [
                    "midnightGlow": ["CFBundleIconFiles": ["MidnightGlow60x60"]],
                ],
            ],
        ]

        XCTAssertEqual(
            AppIconStore.availableIcons(in: infoDictionary)[1].displayName,
            "Midnight Glow"
        )
    }

    func testAvailableIconsHandlesIconComposerEntriesWithoutIconFiles() {
        let infoDictionary: [String: Any] = [
            "CFBundleIcons": [
                "CFBundleAlternateIcons": [
                    "Liquidy": ["CFBundleIconName": "Liquidy"],
                    "Trees": ["CFBundleIconName": "Trees"],
                ],
            ],
            "OpenClientAlternateIconPreviewFiles": [
                "Liquidy": "Liquidy.png",
                "Trees": "Trees.png",
            ],
        ]

        XCTAssertEqual(
            AppIconStore.availableIcons(in: infoDictionary).map(\.iconFiles),
            [[], ["Liquidy.png"], ["Trees.png"]]
        )
    }

    #if canImport(UIKit)
    func testBuiltAppExposesConfiguredAlternateIcons() {
        let store = AppIconStore()

        XCTAssertTrue(store.supportsAlternateIcons)
        XCTAssertEqual(store.icons.map(\.alternateIconName), [nil, "Liquidy", "Trees"])
        XCTAssertEqual(store.icons.map(\.iconFiles), [["AppIcon60x60"], ["Liquidy.png"], ["Trees.png"]])
    }

    func testConfiguredPreviewFilesLoadFromBundle() throws {
        let liquidyPath = try XCTUnwrap(Bundle.main.path(forResource: "Liquidy.png", ofType: nil))
        let treesPath = try XCTUnwrap(Bundle.main.path(forResource: "Trees.png", ofType: nil))

        XCTAssertNotNil(UIImage(contentsOfFile: liquidyPath))
        XCTAssertNotNil(UIImage(contentsOfFile: treesPath))
    }
    #endif
}
