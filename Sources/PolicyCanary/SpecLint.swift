import Foundation

/// The three sections an original-design spec needs before an agent sees it.
public enum SpecSection: String, Sendable, Hashable, CaseIterable {
    case behaviour = "Behaviour"
    case constraints = "Constraints"
    case acceptance = "Acceptance"
}

public enum LintVerdict: Sendable, Hashable {
    /// Describes what to build on its own terms.
    case ready
    /// Original, but missing sections the agent will otherwise guess at.
    case incomplete(missing: [SpecSection])
    /// Defines the work by pointing at someone else's product. Rewrite it as behaviour.
    case rewrite(anchors: [String])

    public var isReady: Bool { self == .ready }
}

/// Flags "build X like Y" prompts and checks that a spec states behaviour, constraints and
/// acceptance criteria. It is deliberately dumb: phrase matching, not judgement. The point
/// is to put the question in code review, not to replace the reviewer.
public enum SpecLint {
    /// Phrases that define work by reference to an existing product.
    public static let anchorPhrases = [
        "clone of", "a clone", "copy of", "recreate", "remake of", "port of",
        "exactly like", "just like", "same as", "pixel-perfect",
    ]

    public static func lint(_ spec: String) -> LintVerdict {
        let anchors = anchorsIn(spec)
        if !anchors.isEmpty { return .rewrite(anchors: anchors) }
        let missing = missingSections(in: spec)
        return missing.isEmpty ? .ready : .incomplete(missing: missing)
    }

    /// Anchor phrases found in the spec, plus any "like <CapitalisedName>" reference.
    public static func anchorsIn(_ spec: String) -> [String] {
        let lower = spec.lowercased()
        var found = anchorPhrases.filter { lower.contains($0) }
        let words = spec.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for index in words.indices where words[index].lowercased() == "like" {
            let next = index + 1
            guard next < words.count, let first = words[next].first, first.isUppercase else { continue }
            let name = words[next].trimmingCharacters(in: .punctuationCharacters)
            found.append("like \(name)")
        }
        return found
    }

    public static func missingSections(in spec: String) -> [SpecSection] {
        let headers = spec.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return SpecSection.allCases.filter { section in
            let names = section == .behaviour ? ["behaviour:", "behavior:"] : [section.rawValue.lowercased() + ":"]
            return !headers.contains { line in names.contains { line.hasPrefix($0) } }
        }
    }
}
