/// How a probe's outcome moved between two runs.
public enum DriftKind: String, Sendable, Hashable {
    case stable
    /// Completed before, refused now.
    case newRefusal
    /// Refused before, completed now.
    case newlyAllowed
    /// The current observation came from a warm session, so it is excluded from any decision.
    case contaminated
    /// No usable (fresh) baseline to compare against.
    case noBaseline
    /// The current run has no observation for this probe.
    case unobserved
}

/// Who could have changed the behaviour.
public enum Attribution: Sendable, Hashable, CustomStringConvertible {
    case none
    /// The client was upgraded between runs, so the changelog is a place to look.
    case clientRelease(from: String, to: String)
    /// Same client build in both runs. The behaviour changed somewhere you don't ship:
    /// a server-side rule, a model swap or a system prompt. No changelog will explain it.
    case vendorSide

    public var description: String {
        switch self {
        case .none: return "none"
        case let .clientRelease(from, to): return "client \(from) → \(to)"
        case .vendorSide: return "vendor-side (same client build)"
        }
    }
}

public struct ProbeDrift: Sendable, Hashable, Identifiable {
    public var id: String { probe.id }
    public let probe: Probe
    public let before: Outcome?
    public let after: Outcome?
    public let kind: DriftKind
    public let attribution: Attribution

    /// True when the current outcome is what the team expects from today's policy.
    public var matchesExpectation: Bool { after == probe.expected }
}

/// What the suite tells the team to do.
public enum Action: Sendable, Hashable {
    case none
    /// Tell the owners; nobody's workflow is blocked.
    case notify(owners: [String])
    /// A blocking task class started refusing. Stop routing that work to the agent,
    /// tell the owners, and run the documented fallback.
    case freeze(probeIDs: [String], owners: [String])
}

public struct DriftReport: Sendable {
    public let baseline: Run
    public let current: Run
    public let drifts: [ProbeDrift]

    public var changed: [ProbeDrift] { drifts.filter { $0.kind == .newRefusal || $0.kind == .newlyAllowed } }
    public var newRefusals: [ProbeDrift] { drifts.filter { $0.kind == .newRefusal } }
    public var contaminated: [ProbeDrift] { drifts.filter { $0.kind == .contaminated } }

    /// True when at least one change happened with the same client build on both sides.
    public var hasVendorSideDrift: Bool { changed.contains { $0.attribution == .vendorSide } }

    public var action: Action {
        let blocking = newRefusals.filter { $0.probe.criticality == .blocking }
        if !blocking.isEmpty {
            return .freeze(probeIDs: blocking.map(\.probe.id), owners: Self.owners(of: blocking))
        }
        if !changed.isEmpty {
            return .notify(owners: Self.owners(of: changed))
        }
        return .none
    }

    private static func owners(of drifts: [ProbeDrift]) -> [String] {
        Array(Set(drifts.map(\.probe.owner))).sorted()
    }
}

public enum DriftDetector {
    /// Compares two runs probe by probe. Only fresh-session observations count: a refusal
    /// from a session that already carries memory or history is reported as `.contaminated`
    /// and never triggers an action, and a warm baseline is treated as no baseline.
    public static func compare(baseline: Run, current: Run, probes: [Probe]) -> DriftReport {
        let sameClient = baseline.clientVersion == current.clientVersion
        let drifts = probes.map { probe -> ProbeDrift in
            let base = baseline.observation(for: probe.id).flatMap { $0.freshSession ? $0 : nil }
            guard let now = current.observation(for: probe.id) else {
                return ProbeDrift(probe: probe, before: base?.outcome, after: nil, kind: .unobserved, attribution: .none)
            }
            guard now.freshSession else {
                return ProbeDrift(probe: probe, before: base?.outcome, after: now.outcome, kind: .contaminated, attribution: .none)
            }
            guard let before = base?.outcome else {
                return ProbeDrift(probe: probe, before: nil, after: now.outcome, kind: .noBaseline, attribution: .none)
            }
            let kind: DriftKind
            switch (before, now.outcome) {
            case (.completed, .refused): kind = .newRefusal
            case (.refused, .completed): kind = .newlyAllowed
            default: kind = .stable
            }
            let attribution: Attribution = kind == .stable
                ? .none
                : (sameClient ? .vendorSide : .clientRelease(from: baseline.clientVersion, to: current.clientVersion))
            return ProbeDrift(probe: probe, before: before, after: now.outcome, kind: kind, attribution: attribution)
        }
        return DriftReport(baseline: baseline, current: current, drifts: drifts)
    }
}
