import Foundation
import XCTest
#if canImport(UIKit)
import UIKit
#endif

@MainActor
private var rotatesSnapshotLandscapeOutput = false

@MainActor
func setSnapshotLandscapeOutput(_ enabled: Bool) {
    rotatesSnapshotLandscapeOutput = enabled
}

@MainActor
func setupSnapshot(_ app: XCUIApplication) {
    app.launchEnvironment["FASTLANE_SNAPSHOT"] = "YES"
    app.launchEnvironment["FASTLANE_LANGUAGE"] = Locale.current.identifier
}

@MainActor
func snapshot(_ name: String, waitForLoadingIndicator: Bool = true) {
    let sanitizedName = name.replacingOccurrences(of: " ", with: "_")
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "\(simulatorIdentifier())-\(sanitizedName)"
    attachment.lifetime = .keepAlways
    XCTContext.runActivity(named: "Snapshot \(sanitizedName)") { activity in
        activity.add(attachment)
    }

    writeScreenshotPNG(landscapeAdjustedPNGData(from: screenshot.pngRepresentation), name: sanitizedName)
}

@MainActor
private func landscapeAdjustedPNGData(from data: Data) -> Data {
    #if canImport(UIKit)
    guard isIPadScreenshotTarget(),
          let image = UIImage(data: data),
          let cgImage = image.cgImage,
          cgImage.width < cgImage.height else {
        return data
    }

    let rotatedSize = CGSize(width: cgImage.height, height: cgImage.width)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
    let rawImage = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    let rotatedImage = renderer.image { context in
        context.cgContext.translateBy(x: 0, y: rotatedSize.height)
        context.cgContext.rotate(by: -.pi / 2)
        rawImage.draw(at: .zero)
    }
    return rotatedImage.pngData() ?? data
    #else
    return data
    #endif
}

@MainActor
private func isIPadScreenshotTarget() -> Bool {
    if rotatesSnapshotLandscapeOutput {
        return true
    }

    let environment = ProcessInfo.processInfo.environment
    if environment["OPENCLIENT_SCREENSHOT_LANDSCAPE_OUTPUT"] == "1" {
        return true
    }

    return [
        environment["SIMULATOR_DEVICE_NAME"],
        environment["SIMULATOR_MODEL_IDENTIFIER"],
    ]
    .compactMap { $0 }
    .contains { $0.localizedCaseInsensitiveContains("iPad") }
}

private func writeScreenshotPNG(_ data: Data, name: String) {
    let locale = ProcessInfo.processInfo.environment["FASTLANE_LANGUAGE"] ?? Locale.current.identifier
    let outputRoot = ProcessInfo.processInfo.environment["OPENCLIENT_SCREENSHOT_OUTPUT_DIR"] ?? defaultScreenshotOutputRoot()
    let directoryURL = URL(fileURLWithPath: outputRoot, isDirectory: true).appendingPathComponent(locale, isDirectory: true)

    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let filename = "\(simulatorIdentifier())-\(name).png"
        try data.write(to: directoryURL.appendingPathComponent(filename))
    } catch {
        XCTFail("Failed to write screenshot \(name): \(error.localizedDescription)")
    }
}

private func defaultScreenshotOutputRoot() -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fastlane", isDirectory: true)
        .appendingPathComponent("screenshots", isDirectory: true)
        .path
}

private func simulatorIdentifier() -> String {
    let environment = ProcessInfo.processInfo.environment
    let raw = environment["SIMULATOR_DEVICE_NAME"] ?? environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "simulator"
    return raw.replacingOccurrences(of: " ", with: "-")
}
