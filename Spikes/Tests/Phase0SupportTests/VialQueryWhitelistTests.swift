import Foundation
import XCTest
@testable import Phase0Support

final class VialQueryWhitelistTests: XCTestCase {
    func testExactWhitelistBuildsExpectedFixedReports() throws {
        let cases: [(VialQuery, [UInt8])] = [
            (.protocolVersion, [0xFE, 0x00]),
            (.uid, [0xFE, 0x00]),
            (.definition(.size), [0xFE, 0x01]),
            (.definition(.page(0x0234)), [0xFE, 0x02, 0x34, 0x02]),
            (.keymapRead(offset: 0x1234, length: 28), [0x12, 0x12, 0x34, 0x1C]),
        ]
        for (query, prefix) in cases {
            let report = try VialQueryReport.make(query)
            XCTAssertEqual(report.bytes.count, 32)
            XCTAssertEqual(Array(report.bytes.prefix(prefix.count)), prefix)
            XCTAssertTrue(report.bytes.dropFirst(prefix.count).allSatisfy { $0 == 0 })
        }
    }

    func testRejectedOpcodeAndMutationFamiliesNeverInvokeTransport() throws {
        for opcode: UInt8 in [0x03, 0x05, 0x06, 0x07, 0x08, 0x0B, 0x0C, 0x0D, 0x13, 0x15, 0xFF] {
            let transport = RecordedVialTransport(exchanges: [])
            XCTAssertThrowsError(try VialOpcodeGate.execute(
                opcode: opcode, payload: [], through: transport, timeoutMilliseconds: 250
            ))
            XCTAssertEqual(transport.callCount, 0)
        }
        for command: UInt8 in [0x04, 0x06, 0x07, 0x08, 0x0B, 0x0C, 0x0D] {
            let transport = RecordedVialTransport(exchanges: [])
            XCTAssertThrowsError(try VialOpcodeGate.execute(
                opcode: 0xFE, payload: [command], through: transport, timeoutMilliseconds: 250
            ))
            XCTAssertEqual(transport.callCount, 0)
        }
    }

    func testReportLengthBoundsReject() throws {
        XCTAssertThrowsError(try VialQueryReport.make(.keymapRead(offset: 0, length: 0)))
        XCTAssertThrowsError(try VialQueryReport.make(.keymapRead(offset: 0, length: 29)))
    }

    func testAggregateDefinitionAndKeymapBoundsRejectAtPublicReportBoundary() throws {
        let maximumPage = UInt16((VialQueryLimits.maximumDefinitionBytes - 1) / 32)
        XCTAssertNoThrow(try VialQueryReport.make(.definition(.page(maximumPage))))
        XCTAssertThrowsError(try VialQueryReport.make(.definition(.page(maximumPage + 1))))
        XCTAssertThrowsError(try VialQueryReport.make(.definition(.page(UInt16.max))))

        let endpointOffset = UInt16(VialQueryLimits.maximumKeymapBytes - VialQueryLimits.maximumKeymapChunkBytes)
        XCTAssertNoThrow(try VialQueryReport.make(.keymapRead(
            offset: endpointOffset, length: UInt8(VialQueryLimits.maximumKeymapChunkBytes)
        )))
        XCTAssertThrowsError(try VialQueryReport.make(.keymapRead(
            offset: endpointOffset + 1, length: UInt8(VialQueryLimits.maximumKeymapChunkBytes)
        )))
        XCTAssertThrowsError(try VialQueryReport.make(.keymapRead(offset: UInt16.max, length: 1)))
        XCTAssertThrowsError(try VialQueryReport.make(.keymapRead(offset: UInt16.max, length: UInt8.max)))
    }

    func testPublicReportSourceIsClosedAndContainsNoRawEscapeHatch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Spikes/Sources/Phase0Support/VialQuery.swift"))
        XCTAssertEqual(try VialSourceContract.validate(source), VialSourceContract.expectedCases)
        XCTAssertFalse(source.contains("public init(bytes:"))
        XCTAssertFalse(source.contains("case write"))
        XCTAssertFalse(source.contains("case unlock"))
        XCTAssertFalse(source.contains("case reset"))
        XCTAssertFalse(source.contains("case bootloader"))
        XCTAssertFalse(source.contains("case macro"))
    }

}
