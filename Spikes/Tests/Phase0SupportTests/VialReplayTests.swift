import Foundation
import XCTest
@testable import Phase0Support

final class VialReplayTests: XCTestCase {
    func testRecordedReplayReconstructsIdentityDefinitionAndKeymapInExactOrder() throws {
        let fixture = try VialRecordedFixture.load(repository: repositoryRoot())
        let transport = RecordedVialTransport(exchanges: fixture.exchanges)
        let result = try VialQueryReplay.run(
            transport: transport, expectedUID: fixture.expectedUID,
            expectedDefinition: fixture.expectedDefinition, expectedKeymap: fixture.expectedKeymap,
            timeoutMilliseconds: 250
        )
        XCTAssertEqual(result.protocolVersion, 6)
        XCTAssertEqual(result.uid, fixture.expectedUID)
        XCTAssertEqual(result.definition, fixture.expectedDefinition)
        XCTAssertEqual(result.keymap, fixture.expectedKeymap)
        XCTAssertEqual(result.definitionSha256, fixture.expectedDefinitionSha256)
        XCTAssertEqual(result.keymapKeycodes, [0x0004, 0x0005, 0x0028, 0x0029])
        XCTAssertEqual(transport.reports.map(\.bytes), fixture.exchanges.map(\.request))
        XCTAssertEqual(transport.callCount, 6)
        XCTAssertNoThrow(try transport.assertExhausted())
    }

    func testTimeoutTruncationWrongUIDExtraReorderAndDuplicateReject() throws {
        try assertReplayError(.timeout, fixture: .timeout)
        try assertReplayError(.truncatedResponse, fixture: .truncated)
        try assertReplayError(.uidMismatch, fixture: .wrongUID)
        try assertReplayError(.extraResponse, fixture: .extra)
        try assertReplayError(.unexpectedRequest, fixture: .reordered)
        try assertReplayError(.unexpectedRequest, fixture: .duplicate)
    }

    func testResponseOnlyDefinitionPageSwapAndDuplicateReject() throws {
        let approved = VialRecordedFixture.approved
        var swapped = approved.exchanges
        swapped.swapAt(3, 4)
        swapped[3] = .init(request: approved.exchanges[3].request, response: swapped[3].response)
        swapped[4] = .init(request: approved.exchanges[4].request, response: swapped[4].response)
        try assertReplayError(
            .unexpectedResponse,
            fixture: .init(
                exchanges: swapped, expectedUID: approved.expectedUID,
                expectedDefinition: approved.expectedDefinition, expectedKeymap: approved.expectedKeymap
            )
        )

        var duplicated = approved.exchanges
        duplicated[4] = .init(
            request: approved.exchanges[4].request,
            response: approved.exchanges[3].response
        )
        try assertReplayError(
            .unexpectedResponse,
            fixture: .init(
                exchanges: duplicated, expectedUID: approved.expectedUID,
                expectedDefinition: approved.expectedDefinition, expectedKeymap: approved.expectedKeymap
            )
        )
    }

    func testAggregateBoundsRejectBeforeTransport() throws {
        let oversized = VialRecordedFixture.definitionSize(VialQueryLimits.maximumDefinitionBytes + 1)
        let transport = RecordedVialTransport(exchanges: VialRecordedFixture.identityPrefix + [oversized])
        XCTAssertThrowsError(try VialQueryReplay.run(
            transport: transport, expectedUID: VialRecordedFixture.approved.expectedUID,
            expectedDefinition: VialRecordedFixture.approved.expectedDefinition,
            expectedKeymap: VialRecordedFixture.approved.expectedKeymap, timeoutMilliseconds: 250
        )) { XCTAssertEqual($0 as? VialQueryError, .definitionTooLarge) }
        XCTAssertEqual(transport.callCount, 3)

        let unused = RecordedVialTransport(exchanges: [])
        XCTAssertThrowsError(try VialQueryReplay.run(
            transport: unused, expectedUID: VialRecordedFixture.approved.expectedUID,
            expectedDefinition: [],
            expectedKeymap: [UInt8](repeating: 0, count: VialQueryLimits.maximumKeymapBytes + 1),
            timeoutMilliseconds: 250
        )) { XCTAssertEqual($0 as? VialQueryError, .keymapTooLarge) }
        XCTAssertEqual(unused.callCount, 0)
    }

    private func assertReplayError(_ expected: VialQueryError, fixture: VialRecordedFixture) throws {
        let transport = RecordedVialTransport(exchanges: fixture.exchanges)
        XCTAssertThrowsError(try VialQueryReplay.run(
            transport: transport, expectedUID: fixture.expectedUID,
            expectedDefinition: fixture.expectedDefinition, expectedKeymap: fixture.expectedKeymap,
            timeoutMilliseconds: 250
        )) { XCTAssertEqual($0 as? VialQueryError, expected) }
    }
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
