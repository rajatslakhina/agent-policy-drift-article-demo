import XCTest
@testable import PolicyCanary

final class DriftDetectorTests: XCTestCase {
    func testSameClientBuildChangeIsAttributedVendorSide() {
        let report = Sample.report("mon-tue")
        XCTAssertEqual(report.changed.map(\.probe.id), ["P03", "P07"])
        XCTAssertTrue(report.changed.allSatisfy { $0.attribution == .vendorSide })
        XCTAssertTrue(report.hasVendorSideDrift)
    }

    func testBlockingNewRefusalFreezesOnlyThatTaskClass() {
        let report = Sample.report("mon-tue")
        XCTAssertEqual(report.action, .freeze(probeIDs: ["P03"], owners: ["Dana"]))
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
        XCTAssertEqual(report.changed.first?.attribution, .clientRelease(from: "2.1.316", to: "2.1.317"))
        XCTAssertEqual(report.action, .notify(owners: ["Leo"]))
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

    func testMissingObservationIsUnobservedAndTriggersNothing() {
        let probe = Sample.probes[0]
        let base = Run(id: "a", label: "A", clientVersion: "1", observations: [Observation(probeID: probe.id, outcome: .completed)])
        let empty = Run(id: "b", label: "B", clientVersion: "1", observations: [])
        let report = DriftDetector.compare(baseline: base, current: empty, probes: [probe])
        XCTAssertEqual(report.drifts.first?.kind, .unobserved)
        XCTAssertEqual(report.action, .none)
    }

    func testNoProbesMeansNoAction() {
        let report = DriftDetector.compare(baseline: Sample.monday, current: Sample.tuesday, probes: [])
        XCTAssertTrue(report.drifts.isEmpty)
        XCTAssertEqual(report.action, .none)
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
