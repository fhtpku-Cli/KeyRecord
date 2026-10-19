import Foundation
import AppKit
import SwiftUI
import XCTest
import KeyRecordCore

final class UpdateStubProtocol: URLProtocol, @unchecked Sendable {
    static let responseData = Data(#"{"tag_name":"v1.2.3","draft":false,"prerelease":false}"#.utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url, UpdateHTTPClient.endpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let response = HTTPURLResponse(url: UpdateHTTPClient.endpoint, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UpdateOversizedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: UpdateHTTPClient.endpoint, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: UpdateHTTPClient.maximumBytes + 1))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UpdateUnavailableProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: UpdateHTTPClient.endpoint, statusCode: 404,
            httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

class UpdateBadResponseProtocol: URLProtocol, @unchecked Sendable {
    class var status: Int { 500 }
    class var mime: String { "application/json" }
    class var length: Int { 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: UpdateHTTPClient.endpoint, statusCode: Self.status,
            httpVersion: nil, headerFields: ["Content-Type": Self.mime, "Content-Length": String(Self.length)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class UpdateWrongMIMEProtocol: UpdateBadResponseProtocol, @unchecked Sendable {
    override class var status: Int { 200 }
    override class var mime: String { "text/html" }
}
final class UpdateDeclaredOversizeProtocol: UpdateBadResponseProtocol, @unchecked Sendable {
    override class var status: Int { 200 }
    override class var length: Int { UpdateHTTPClient.maximumBytes + 1 }
}

final class UpdatesTests: XCTestCase {
    func testHTTPFailuresAndDeclaredOversizeAreRejected() async {
        for stub in [UpdateBadResponseProtocol.self, UpdateWrongMIMEProtocol.self, UpdateDeclaredOversizeProtocol.self] {
            do { _ = try await UpdateHTTPClient.fetch(protocolClasses: [stub]); XCTFail("Accepted invalid response") }
            catch {}
        }
    }
    func testRedirectDelegateRefusesNewRequest() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: UpdateHTTPClient.endpoint)
        let response = HTTPURLResponse(url: UpdateHTTPClient.endpoint, statusCode: 302,
            httpVersion: nil, headerFields: ["Location": "https://example.invalid"])!
        UpdateHTTPClient().urlSession(session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://example.invalid")!)) { request in
                XCTAssertNil(request)
            }
        task.cancel()
    }
    @MainActor
    func testNativeCheckAndConfirmationInBothLanguages() throws {
        ScreenEvidence.prepare()
        for locale in ["en", "zh-Hans"] {
            let model = UpdatesModel(), text = NativeText(locale: locale)
            var opened = 0
            model.configure(UpdatePorts(currentVersion: "0.1", fetch: { UpdateStubProtocol.responseData },
                open: { _ in opened += 1; return true }))
            let view = NSHostingView(rootView: Form {
                UpdatesSection(model: model, text: text)
            }.formStyle(.grouped).frame(width: 680, height: 540))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
            defer { window.contentView = nil; window.close() }
            NativeEvidence.primeAccessibility(); NativeEvidence.update(view); NativeEvidence.update(view)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("updates.check", in: view)))
            ScreenEvidence.awaitMain {
                for _ in 0..<100 {
                    if model.available != nil { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            NativeEvidence.update(view)
            XCTAssertEqual(KRAXLabel(try NativeEvidence.node("updates.status", in: view)), text("updates.available"))
            XCTAssertEqual(opened, 0)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("updates.review", in: view)))
            NativeEvidence.update(view)
            XCTAssertTrue(model.reviewing)
            XCTAssertEqual(opened, 0)
            let sheet = try XCTUnwrap(window.attachedSheet?.contentView)
            NativeEvidence.update(sheet)
            XCTAssertTrue(KRAXPress(try NativeEvidence.node("updates.open", in: sheet)))
            NativeEvidence.update(view)
            XCTAssertEqual(opened, 1)
            XCTAssertFalse(model.reviewing)
        }
    }
    func testTransportUsesFixedEmptyGETAndBoundsActualBytes() async throws {
        let bytes = try await UpdateHTTPClient.fetch(protocolClasses: [UpdateStubProtocol.self])
        XCTAssertEqual(bytes, UpdateStubProtocol.responseData)
        let missing = try await UpdateHTTPClient.fetch(protocolClasses: [UpdateUnavailableProtocol.self])
        XCTAssertNil(missing)
        do {
            _ = try await UpdateHTTPClient.fetch(protocolClasses: [UpdateOversizedProtocol.self])
            XCTFail("Accepted oversized response")
        } catch {}
    }
    @MainActor
    func testSchedulePersistsAttemptsAndOpeningRequiresReview() async throws {
        var last: Date?
        var opened: [URL] = []
        let now = Date(timeIntervalSince1970: 1000000)
        let model = UpdatesModel()
        model.configure(UpdatePorts(currentVersion: "0.1", now: { now }, lastAttempt: { last },
            saveAttempt: { last = $0 }, clearAttempt: { last = nil },
            fetch: { UpdateStubProtocol.responseData }, open: { opened.append($0); return true }))
        await model.check(manual: false)
        XCTAssertEqual(last, now)
        XCTAssertEqual(model.available?.tag, "v1.2.3")
        model.confirmOpen()
        XCTAssertTrue(opened.isEmpty)
        model.requestReview(); model.confirmOpen()
        XCTAssertEqual(opened.map(\.absoluteString), [UpdateHTTPClient.releasePrefix + "v1.2.3"])
        model.cancel()
        await model.check(manual: false)
        XCTAssertNil(model.available)
        await model.check(manual: true)
        XCTAssertNotNil(model.available)
        model.eraseHistory()
        XCTAssertNil(last); XCTAssertNil(model.lastAttempt)
    }
    @MainActor
    func testFailuresNeverClaimCurrentAndMalformedVersionMakesNoRequest() async {
        let model = UpdatesModel()
        model.configure(UpdatePorts(currentVersion: "0.1", fetch: { throw URLError(.timedOut) }))
        await model.check(manual: true)
        XCTAssertEqual(model.message, "updates.failed")
        model.configure(UpdatePorts(currentVersion: "broken", fetch: { XCTFail("Unexpected request"); return nil }))
        await model.check(manual: true)
        XCTAssertEqual(model.message, "updates.invalidVersion")
    }
    @MainActor
    func testCancelledLateResponseCannotRestoreAvailability() async {
        let model = UpdatesModel()
        model.configure(UpdatePorts(currentVersion: "0.1", fetch: {
            try? await Task.sleep(for: .milliseconds(100))
            return UpdateStubProtocol.responseData
        }))
        let task = Task { await model.check(manual: true) }
        while !model.busy { await Task.yield() }
        model.cancel()
        await task.value
        XCTAssertNil(model.available); XCTAssertFalse(model.busy)
    }
    func testLicensesAreBundledAndOnlyAllowlistedNamesReadable() throws {
        XCTAssertTrue(try XCTUnwrap(LicenseNotices.content("LICENSE")).contains("Version 2.0"))
        XCTAssertTrue(try XCTUnwrap(LicenseNotices.content("NOTICE")).contains("KeyRecord"))
        XCTAssertTrue(try XCTUnwrap(LicenseNotices.content("Argon2-LICENSE.txt")).contains("Apache"))
        XCTAssertNil(LicenseNotices.content("../Info.plist"))
    }
}
