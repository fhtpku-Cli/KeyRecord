import Foundation
import XCTest
import KeyRecordCore
import KeyRecordTestSupport

final class LifecycleBoundaryTests: XCTestCase {
    private let lifecycleFiles = [
        "LifecycleReducer.swift", "LifecycleTransitions.swift", "LifecyclePauseTransitions.swift",
        "LifecycleReopenTransitions.swift", "LifecyclePorts.swift", "LifecycleOrchestrator.swift",
        "LoginItemPolicy.swift", "PreferencesRepository.swift",
    ]

    func testLifecycleFilesStayUnder250LinesAndImportOnlyFoundation() throws {
        // Given: every lifecycle production file; When: measured; Then: size limit and import allowlist hold.
        let directory = SourceInspection.root.appendingPathComponent("Sources/KeyRecordCore")
        for name in lifecycleFiles {
            let url = directory.appendingPathComponent(name)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertLessThan(source.split(separator: "\n", omittingEmptySubsequences: false).count, 250, name)
            XCTAssertEqual(try SourceInspection.imports(in: source), ["Foundation"], name)
        }
    }

    func testRootSourcesContainNoLoginKeychainOrTapSystemEffects() throws {
        // Given: all root product sources; When: scanned by module; Then: effects stay at their boundaries.
        for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Sources")) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let code = SourceInspection.codeOnly(text)
            for symbol in ["SMAppService", "ServiceManagement", "SecItemAdd", "SecItemCopyMatching"] {
                XCTAssertFalse(code.contains(symbol), "\(symbol) must not appear in \(file.lastPathComponent)")
            }
            let isCore = file.path.contains("/Sources/KeyRecordCore/")
            let isStore = file.path.contains("/Sources/KeyRecordStore/")
            let isCapture = file.path.contains("/Sources/KeyRecordCapture/")
            for symbol in ["CGEventPost", "CGEvent.tapCreate", "dlopen", "dlsym"] {
                // Decision cores have zero system symbols; event/private HIToolbox bridges
                // belong only in isolated Capture System*Backend.swift thin backends.
                if isCore || isStore {
                    XCTAssertFalse(code.contains(symbol), "\(symbol) must not appear in \(file.lastPathComponent)")
                }
                if isCapture, code.contains(symbol) {
                    XCTAssertTrue(file.lastPathComponent.hasPrefix("System"), "\(symbol) requires a system backend in \(file.lastPathComponent)")
                    XCTAssertTrue(file.lastPathComponent.hasSuffix("Backend.swift"), "\(symbol) requires a thin backend in \(file.lastPathComponent)")
                }
            }
        }
    }

    func testSMAppServiceLivesInExactlyOneThinAppBackend() throws {
        // Given: the App source tree; When: scanned; Then: one backend file holds the system API.
        let appFiles = try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("App"))
        var smFiles: [String] = []
        var serviceManagementImports: [String] = []
        for file in appFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            if SourceInspection.codeOnly(text).contains("SMAppService") { smFiles.append(file.lastPathComponent) }
            if try SourceInspection.imports(in: text).contains("ServiceManagement") {
                serviceManagementImports.append(file.lastPathComponent)
            }
        }
        XCTAssertEqual(smFiles, ["SMAppServiceLoginItemBackend.swift"])
        XCTAssertEqual(serviceManagementImports, ["SMAppServiceLoginItemBackend.swift"])
    }

    func testControllersMakeNoDirectSystemLoginOrKeychainCalls() throws {
        // Given: the observable controllers; When: scanned; Then: decisions, never system APIs.
        let app = SourceInspection.root.appendingPathComponent("App/KeyRecordApp")
        for name in ["CaptureController.swift", "LoginItemController.swift"] {
            let code = SourceInspection.codeOnly(try String(
                contentsOf: app.appendingPathComponent(name), encoding: .utf8))
            for symbol in ["SMAppService", "SMApp", "ServiceManagement", "SecItem", "CGEvent"] {
                XCTAssertFalse(code.contains(symbol), "\(symbol) must stay out of \(name)")
            }
        }
    }

    func testAppTreeNeverTouchesKeychainDirectly() throws {
        // Given: App sources; When: scanned; Then: key operations remain behind the task-11 port boundary.
        for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("App")) {
            let code = SourceInspection.codeOnly(try String(contentsOf: file, encoding: .utf8))
            for symbol in ["SecItemAdd", "SecItemDelete", "SecItemUpdate", "SecItemCopyMatching"] {
                XCTAssertFalse(code.contains(symbol), "\(symbol) must not appear in \(file.lastPathComponent)")
            }
        }
    }

    func testTestSourcesNeverImportTheConcreteLoginServiceModule() throws {
        // Given: all root tests; When: imports are scanned; Then: no test path can see SMAppService APIs.
        for file in try SourceInspection.swiftFiles(in: SourceInspection.root.appendingPathComponent("Tests")) {
            let code = SourceInspection.codeOnly(try String(contentsOf: file, encoding: .utf8))
            XCTAssertFalse(try SourceInspection.imports(in: code).contains("ServiceManagement"), file.lastPathComponent)
        }
    }

    func testLifecycleExposesNoDirectTimeOrFileIO() throws {
        // Given: lifecycle sources; When: scanned; Then: time and filesystem stay behind injected ports.
        let directory = SourceInspection.root.appendingPathComponent("Sources/KeyRecordCore")
        for name in lifecycleFiles {
            let code = SourceInspection.codeOnly(try String(
                contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
            for symbol in ["Date()", "FileManager", "URL(fileURLWithPath", "DispatchQueue", "print(", "NSLog("] {
                XCTAssertFalse(code.contains(symbol), "\(symbol) must not appear in \(name)")
            }
        }
    }
}
