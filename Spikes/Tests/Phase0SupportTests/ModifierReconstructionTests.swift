import XCTest
@testable import Phase0Support

final class ModifierReconstructionTests: XCTestCase {
    func testEverySidedFamilyReachesNoneLeftRightBothAndUnknown() {
        for family in ModifierFamily.allCases {
            var model = ModifierReconstructionModel()
            XCTAssertEqual(model[family], .activeSideUnknown)
            model.apply(family: family, left: false, right: false)
            XCTAssertEqual(model[family], .none)
            model.apply(family: family, left: true, right: false)
            XCTAssertEqual(model[family], .left)
            model.apply(family: family, left: false, right: true)
            XCTAssertEqual(model[family], .right)
            model.apply(family: family, left: true, right: true)
            XCTAssertEqual(model[family], .both)
            model.markLoss(affected: [family])
            XCTAssertEqual(model[family], .activeSideUnknown)
        }
    }

    func testLossOnlyPoisonsAffectedFamilyUntilDeterministicFamilySnapshot() {
        var model = ModifierReconstructionModel()
        for family in ModifierFamily.allCases { model.apply(family: family, left: true, right: false) }
        model.markLoss(affected: [.command])
        XCTAssertEqual(model[.command], .activeSideUnknown)
        XCTAssertTrue(ModifierFamily.allCases.filter { $0 != .command }.allSatisfy { model[$0] == .left })
        model.apply(family: .command, left: false, right: true)
        XCTAssertEqual(model[.command], .right)
    }

    func testResetAndWakePoisonAllFamiliesAndFnUntilDeterministicRecovery() {
        for transition in RecoveryTransition.allCases {
            var model = ModifierReconstructionModel()
            for family in ModifierFamily.allCases { model.apply(family: family, left: true, right: false) }
            model.applyFn(active: true)
            model.invalidate(for: transition)
            XCTAssertTrue(ModifierFamily.allCases.allSatisfy { model[$0] == .activeSideUnknown })
            XCTAssertEqual(model.fn, .unknown)
            XCTAssertFalse(model.canCountFnSensitiveChord)
            model.apply(family: .shift, left: false, right: false)
            XCTAssertEqual(model.fn, .unknown, "family recovery cannot infer Fn")
            model.applyFn(active: false)
            XCTAssertEqual(model.fn, .knownNone)
            XCTAssertTrue(model.canCountFnSensitiveChord)
        }
    }

    func testFnKnownNoneKnownActiveUnknownAndDeterministicRecovery() {
        var model = ModifierReconstructionModel()
        XCTAssertEqual(model.fn, .unknown)
        model.applyFn(active: false)
        XCTAssertEqual(model.fn, .knownNone)
        model.applyFn(active: true)
        XCTAssertEqual(model.fn, .knownActive)
        model.invalidate(for: .eventLoss)
        XCTAssertEqual(model.fn, .unknown)
        model.applyFn(active: true)
        XCTAssertEqual(model.fn, .knownActive)
    }

    func testIdenticalSnapshotsRecoverDeterministicallyAcrossRuns() {
        func recovered() -> ModifierReconstructionModel {
            var model = ModifierReconstructionModel()
            model.invalidate(for: .tapReset)
            for family in ModifierFamily.allCases { model.apply(family: family, left: family == .command, right: family == .option) }
            model.applyFn(active: false)
            return model
        }
        XCTAssertEqual(recovered(), recovered())
    }
}
