import Foundation
import AppKit
import SwiftUI
import XCTest

// MARK: - Task 22 source inspection (DESIGN §3: semantic colors only, no custom RGB)

enum SourceInspection {
    /// Space-insensitive substrings; matched against each line with whitespace removed.
    static let forbiddenColorPatterns: [(token: String, reason: String)] = [
        ("Color(red:", "hardcoded RGB Color"),
        ("Color(hue:", "hardcoded HSB Color"),
        ("Color(displayP3", "hardcoded DisplayP3 Color"),
        ("Color(.sRGB", "hardcoded sRGB Color"),
        ("NSColor(red:", "hardcoded RGB NSColor"),
        ("NSColor(calibratedRed:", "hardcoded RGB NSColor"),
        ("NSColor(deviceRed:", "hardcoded RGB NSColor"),
        ("NSColor(sRGBRed:", "hardcoded RGB NSColor"),
        ("NSColor(hue:", "hardcoded HSB NSColor"),
        ("NSColor(calibratedHue:", "hardcoded HSB NSColor"),
        ("NSColor(deviceHue:", "hardcoded HSB NSColor"),
        (".foregroundColor(.white)", "absolute foreground color"),
        (".foregroundColor(.black)", "absolute foreground color"),
        (".foregroundStyle(.white)", "absolute foreground style"),
        (".foregroundStyle(.black)", "absolute foreground style"),
        ("Color.white", "absolute Color constant"),
        ("Color.black", "absolute Color constant"),
    ]

    /// Line-numbered violations; an empty result is the pass condition.
    static func hardcodedColorViolations(_ source: String, file: String) -> [String] {
        var violations: [String] = []
        for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let compact = line.replacingOccurrences(of: " ", with: "")
            for (token, reason) in forbiddenColorPatterns where compact.contains(token) {
                violations.append("\(file):\(index + 1): \(reason): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return violations
    }
}

@MainActor
final class T22AppearanceTests: XCTestCase {
    private func luminance(_ color: NSColor) throws -> Double {
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    private func ratio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func testSemanticTextAndControlPaletteMeetsContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var colors: [NSColor] = []
            appearance.performAsCurrentDrawingAppearance {
                colors = [NSColor.labelColor, .controlTextColor, .windowBackgroundColor, .controlBackgroundColor]
                    .compactMap { $0.usingColorSpace(.sRGB) }
            }
            XCTAssertEqual(colors.count, 4)
            let values = try colors.map(luminance)
            for foreground in values.prefix(2) {
                for background in values.suffix(2) {
                    XCTAssertGreaterThanOrEqual(ratio(foreground, background), 4.5, name.rawValue)
                }
            }
        }
        for source in try LocalizationAudit.appSources() {
            XCTAssertEqual(SourceInspection.hardcodedColorViolations(source.text, file: source.name), [])
            for line in source.text.components(separatedBy: .newlines) where line.contains(".foregroundStyle(") {
                XCTAssertTrue(line.contains(".foregroundStyle(.primary)"), "\(source.name): \(line)")
            }
        }
    }

    func testHighContrastRequestedScreensHaveReadableRenderedInkAndAX() throws {
        for appearance in [MatrixAppearance.highContrastLight, .highContrastDark] {
            for locale in MatrixContent.locales {
                for kind in ScreenKind.allCases {
                    let rendered = try ScreenEvidence.record(kind, fixture: MatrixFixture(
                        state: .collecting, locale: locale, appearance: appearance))
                    defer { ScreenEvidence.close(rendered) }
                    XCTAssertEqual(ScreenEvidence.rawLabelViolations(rendered.view), [])
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: ScreenEvidence.capturePNG(rendered.view)))
                    var measured = 0
                    for node in NativeEvidence.elements(in: rendered.view, includeScrollChrome: false) {
                        guard ["AXStaticText", "AXHeading"].contains(KRAXRole(node) ?? ""),
                              KRAXIdentifier(node) != nil else { continue }
                        let local = rendered.view.convert(rendered.window.convertFromScreen(KRAXFrame(node)), from: nil)
                        guard rendered.view.bounds.contains(local), local.width > 1, local.height > 1 else { continue }
                        let scaleX = CGFloat(bitmap.pixelsWide) / rendered.view.bounds.width
                        let scaleY = CGFloat(bitmap.pixelsHigh) / rendered.view.bounds.height
                        let pixels = NSRect(x: local.minX * scaleX, y: local.minY * scaleY,
                                            width: local.width * scaleX, height: local.height * scaleY)
                        let minX = max(0, Int(pixels.minX)), maxX = min(bitmap.pixelsWide, Int(pixels.maxX))
                        let top = rendered.view.isFlipped ? pixels.minY : CGFloat(bitmap.pixelsHigh) - pixels.maxY
                        let minY = max(0, Int(top)), maxY = min(bitmap.pixelsHigh, Int(top + pixels.height))
                        guard minX < maxX, minY < maxY else {
                            XCTFail("AX crop outside bitmap: \(local), \(pixels)")
                            continue
                        }
                        var darkest = 1.0, lightest = 0.0
                        for y in minY..<maxY {
                            for x in minX..<maxX {
                                let value = try luminance(XCTUnwrap(bitmap.colorAt(x: x, y: y)))
                                darkest = min(darkest, value); lightest = max(lightest, value)
                            }
                        }
                        // Ink cores, not antialiased edges, are compared to the local background.
                        XCTAssertGreaterThanOrEqual(ratio(darkest, lightest), 4.5,
                            "\(kind.rawValue)/\(KRAXIdentifier(node) ?? "-") \(appearance.stem)")
                        measured += 1
                    }
                    XCTAssertGreaterThan(measured, 0, kind.rawValue)
                }
            }
        }
    }

    func testEveryMotionSiteIsGatedAndInjectedTransactionDisablesAnimations() throws {
        let sources = try LocalizationAudit.appSources()
        var sheetFiles = Set<String>(), windowFiles = Set<String>()
        for source in sources {
            XCTAssertFalse(source.text.contains("withAnimation("), source.name)
            XCTAssertFalse(source.text.contains(".animation("), source.name)
            XCTAssertFalse(source.text.contains(".transition("), source.name)
            if source.text.contains(".sheet(") {
                sheetFiles.insert(source.name)
                XCTAssertTrue(source.text.contains(".nativeMotionPolicy()"), source.name)
            }
            if source.text.contains("NSWindow(") {
                windowFiles.insert(source.name)
                XCTAssertTrue(source.text.contains("panel.animationBehavior = .none"), source.name)
            }
        }
        XCTAssertEqual(sheetFiles, ["SettingsFlowView.swift", "PrimitiveShowcase.swift"])
        XCTAssertEqual(windowFiles, ["AnalysisPreview.swift", "ProductComposition.swift", "FlowTestComposition.swift"])
        let probe = MotionProbe()
        ScreenEvidence.prepare()
        let view = NSHostingView(rootView: Text("Motion fixture")
            .transaction { probe.disabled = $0.disablesAnimations; probe.hasAnimation = $0.animation != nil }
            .nativeMotionPolicy().environment(\.nativeReduceMotion, true))
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        NativeEvidence.update(view)
        XCTAssertEqual(probe.disabled, true)
        XCTAssertEqual(probe.hasAnimation, false)
    }
}

@MainActor
private final class MotionProbe {
    var disabled: Bool?
    var hasAnimation: Bool?
}
