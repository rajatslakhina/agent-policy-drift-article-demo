import XCTest
@testable import PolicyCanary

final class DriftDetectorTests: XCTestCase {
    func testSameClientBuildChangeIsAttributedVendorSide() {
        let report = Sample.report("mon-tue")
        XCTAssertEqual(report.changed.map(\.probe.id), ["P03", "P07"])
        XCTAssertTrue(report.changed.allSatisfy { $0.attribution == .vendorSide })
        XCTAssertTrue(report.hasVendorSideDrift)
    }

    func testBlockingNewRefusalFreezesThatTaskClassAndStillNotifiesTheRest() {
        let report = Sample.report("mon-tue")
        XCTAssertEqual(report.action, Action(freezeProbeIDs: ["P03"], freezeOwners: ["Dana"], notifyOwners: ["Leo"]))
    }

    func testStillRefusingBlockingProbeStaysFrozenAfterUpgrade() {
        let report = Sample.report("tue-wed")
        XCTAssertEqual(report.frozen.map(\.probe.id), ["P03"])
        XCTAssertEqual(report.action.freezeOwners, ["Dana"])
    }

    func testWarmSessionRefusalIsContaminatedAndIgnored() {
        let report = Sample.report("mon-tue")
        XCTAssertEqual(report.contaminated.map(\.probe.id), ["P05"])
        XCTAssertFalse(report.newRefusals.contains { $0.probe.id == "P05" })
    }

    func testClientUpgradeChangeIsAttributedToTheRelease() {
        let report = Sample.report("tue-wed")
        XCTAssertEqual(report.changed.map(\.probe.id), ["P07"])
        XCTAssertEqual(report.changed.first?.kind, .newlyAllowed)
        XCTAssertEqual(report.changed.first?.attribution, .clientRelease(from: "5.0.12", to: "5.0.13"))
        XCTAssertEqual(report.action.notifyOwners, ["Leo"])
        XCTAssertFalse(report.hasVendorSideDrift)
    }

    func testWarmBaselineCountsAsNoBaseline() {
        let report = Sample.report("tue-wed")
        XCTAssertEqual(report.drifts.first { $0.probe.id == "P05" }?.kind, .noBaseline)
    }

    func testStillRefusedIsStableButFailsExpectation() {
        let report = Sample.report("tue-wed")
        let p03 = report.drifts.first { $0.probe.id == "P03" }
        XCTAssertEqual(p03?.kind, .stable)
        XCTAssertEqual(p03?.matchesExpectation, false)
    }

    func testNegativeCanaryMatchesWhenRefused() {
        for pair in ["mon-tue", "tue-wed"] {
            let p10 = Sample.report(pair).drifts.first { $0.probe.id == "P10" }
            XCTAssertEqual(p10?.kind, .stable)
            XCTAssertEqual(p10?.matchesExpectation, true)
        }
    }

    func testMissingBlockingObservationNotifiesItsOwner() {
        let probe = Sample.probes[0]
        let base = Run(id: "a", label: "A", clientVersion: "1", observations: [Observation(probeID: probe.id, outcome: .completed)])
        let empty = Run(id: "b", label: "B", clientVersion: "1", observations: [])
        let report = DriftDetector.compare(baseline: base, current: empty, probes: [probe])
        XCTAssertEqual(report.drifts.first?.kind, .unobserved)
        XCTAssertEqual(report.action, Action(notifyOwners: ["Priya"]))
    }

    func testNoProbesMeansNoAction() {
        let report = DriftDetector.compare(baseline: Sample.monday, current: Sample.tuesday, probes: [])
        XCTAssertTrue(report.drifts.isEmpty)
        XCTAssertTrue(report.action.isNone)
    }

    func testDuplicateObservationsKeepTheFirst() {
        let run = Run(id: "d", label: "D", clientVersion: "1", observations: [
            Observation(probeID: "X", outcome: .refused),
            Observation(probeID: "X", outcome: .completed),
        ])
        XCTAssertEqual(run.observation(for: "X")?.outcome, .refused)
    }
}

final class SpecLintTests: XCTestCase {
    func testSampleVerdicts() {
        let verdicts = Dictionary(uniqueKeysWithValues: Sample.probes.map { ($0.id, SpecLint.lint($0.spec)) })
        let rewrite = verdicts.filter { if case .rewrite = $0.value { return true } else { return false } }.keys.sorted()
        XCTAssertEqual(rewrite, ["P03", "P07", "P09"])
        XCTAssertEqual(verdicts["P06"], .incomplete(missing: [.acceptance]))
        XCTAssertEqual(verdicts.values.filter(\.isReady).count, 6)
    }

    func testBothRefusingSpecsAreAnchoredAndNoOriginalSpecRefuses() {
        let refusedOnTuesday = Sample.report("mon-tue").newRefusals.map(\.probe)
        XCTAssertTrue(refusedOnTuesday.allSatisfy { !SpecLint.anchorsIn($0.spec).isEmpty })
        let original = Sample.probes.filter { SpecLint.anchorsIn($0.spec).isEmpty }
        XCTAssertEqual(original.count, 7)
        XCTAssertTrue(original.allSatisfy { !refusedOnTuesday.contains($0) })
    }

    func testLikeFollowedByLowercaseIsNotAnAnchor() {
        XCTAssertTrue(SpecLint.anchorsIn("Feels like a native list. Behaves like any other screen.").isEmpty)
    }

    func testAnchorPhrasesNeedWordBoundaries() {
        XCTAssertTrue(SpecLint.anchorsIn("Add support of dark mode. Fix the import of fonts. Show recreated rows.").isEmpty)
        XCTAssertEqual(SpecLint.anchorsIn("A PORT OF the old screen"), ["port of"])
    }

    func testLikeAtEndOfSpecIsSafe() {
        XCTAssertTrue(SpecLint.anchorsIn("Make it look like").isEmpty)
    }

    func testCapitalisedReferenceIsTrimmed() {
        XCTAssertEqual(SpecLint.anchorsIn("A chart like Stocksy, please."), ["like Stocksy"])
    }

    func testAmericanSpellingCountsAsBehaviourSection() {
        let spec = "Thing.\nBehavior: x\nConstraints: y\nAcceptance: z"
        XCTAssertEqual(SpecLint.lint(spec), .ready)
    }

    func testEmptySpecIsMissingEverything() {
        XCTAssertEqual(SpecLint.lint(""), .incomplete(missing: SpecSection.allCases))
    }
}
