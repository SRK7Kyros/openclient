import XCTest
@testable import OpenClient

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
}
