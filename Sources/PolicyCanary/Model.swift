/// What a coding agent did with a canary task.
public enum Outcome: String, Sendable, Hashable, Codable, CustomStringConvertible {
    case completed
    case refused

    public var description: String { rawValue }
}

/// How much a probe matters to the team's delivery.
public enum Criticality: String, Sendable, Hashable, Codable {
    /// A real workflow depends on this task class. A fresh outcome that fails expectation,
    /// new or carried over, freezes agent work on it.
    case blocking
    /// Worth knowing about, not worth stopping work for.
    case advisory
}

/// One canary task: a short, representative spec from the team's real prompt library,
/// with the outcome the team expects from today's vendor policy.
public struct Probe: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let spec: String
    public let expected: Outcome
    public let criticality: Criticality
    public let owner: String

    public init(id: String, title: String, spec: String, expected: Outcome, criticality: Criticality, owner: String) {
        self.id = id
        self.title = title
        self.spec = spec
        self.expected = expected
        self.criticality = criticality
        self.owner = owner
    }
}

/// What one probe did in one run.
public struct Observation: Sendable, Hashable {
    public let probeID: String
    public let outcome: Outcome
    /// `false` when the probe ran in a session that already had memory, history or earlier
    /// turns. A warm session measures your own history as much as the vendor's policy.
    public let freshSession: Bool

    public init(probeID: String, outcome: Outcome, freshSession: Bool = true) {
        self.probeID = probeID
        self.outcome = outcome
        self.freshSession = freshSession
    }
}

/// One scheduled pass of the whole canary suite.
public struct Run: Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    /// The agent client version installed on the canary machine, e.g. "5.0.12".
    public let clientVersion: String
    public let observations: [Observation]

    public init(id: String, label: String, clientVersion: String, observations: [Observation]) {
        self.id = id
        self.label = label
        self.clientVersion = clientVersion
        self.observations = observations
    }

    /// The observation for a probe, if the run recorded one. Duplicates keep the first.
    public func observation(for probeID: String) -> Observation? {
        observations.first { $0.probeID == probeID }
    }
}
