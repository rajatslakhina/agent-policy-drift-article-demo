import SwiftUI
import PolicyCanary

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// Launch arguments let the screenshot script open a specific screen:
/// `-tab drift|lint` and `-pair mon-tue|tue-wed`.
struct RootView: View {
    @State private var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "drift"

    var body: some View {
        TabView(selection: $tab) {
            DriftView()
                .tabItem { Label("Drift", systemImage: "waveform.path.ecg") }
                .tag("drift")
            LintView()
                .tabItem { Label("Spec lint", systemImage: "text.badge.checkmark") }
                .tag("lint")
        }
    }
}

// MARK: - Drift

struct DriftView: View {
    @State private var pair: String = UserDefaults.standard.string(forKey: "pair") ?? "mon-tue"
    @State private var selected: ProbeDrift?

    private var report: DriftReport { Sample.report(pair) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Compare", selection: $pair) {
                        Text("Mon → Tue").tag("mon-tue")
                        Text("Tue → Wed").tag("tue-wed")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pairPicker")
                    ClientRow(report: report)
                    ActionBanner(action: report.action, vendorSide: report.hasVendorSideDrift)
                }
                Section("\(report.drifts.count) canary probes") {
                    ForEach(report.drifts) { drift in
                        Button { selected = drift } label: { ProbeRow(drift: drift) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("PolicyCanary")
            .sheet(item: $selected) { drift in
                ProbeDetail(drift: drift).presentationDetents([.medium, .large])
            }
        }
    }
}

struct ClientRow: View {
    let report: DriftReport

    var body: some View {
        let same = report.baseline.clientVersion == report.current.clientVersion
        HStack {
            Label("Client \(report.baseline.clientVersion) → \(report.current.clientVersion)", systemImage: "shippingbox")
                .font(.subheadline.monospacedDigit())
            Spacer()
            Text(same ? "unchanged" : "upgraded")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((same ? Color.gray : Color.blue).opacity(0.18), in: Capsule())
        }
    }
}

struct ActionBanner: View {
    let action: Action
    let vendorSide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !action.freezeProbeIDs.isEmpty {
                Label("Freeze agent work on \(action.freezeProbeIDs.joined(separator: ", "))", systemImage: "hand.raised.fill")
                    .font(.headline).foregroundStyle(.red)
                Text("Owner: \(action.freezeOwners.joined(separator: ", ")). Run the documented fallback.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !action.notifyOwners.isEmpty {
                Label("Notify \(action.notifyOwners.joined(separator: ", "))", systemImage: "bell.fill")
                    .font(.subheadline.bold()).foregroundStyle(.orange)
            }
            if action.isNone {
                Label("No drift, nothing failing", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
            }
            if vendorSide {
                Text("Same client build on both runs: no changelog will explain this change.")
                    .font(.caption.bold()).foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension DriftKind {
    var color: Color {
        switch self {
        case .stable: return .green
        case .newRefusal: return .red
        case .newlyAllowed: return .orange
        case .contaminated: return .purple
        case .noBaseline, .unobserved: return .gray
        }
    }

    var label: String {
        switch self {
        case .stable: return "Stable"
        case .newRefusal: return "New refusal"
        case .newlyAllowed: return "Newly allowed"
        case .contaminated: return "Warm session · ignored"
        case .noBaseline: return "No fresh baseline"
        case .unobserved: return "Not run"
        }
    }
}

struct ProbeRow: View {
    let drift: ProbeDrift

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(drift.probe.id).font(.caption.bold().monospaced()).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(drift.probe.title).font(.subheadline)
                    if drift.probe.criticality == .blocking {
                        Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("blocking")
                    }
                }
                Text("\(drift.before?.description ?? "—") → \(drift.after?.description ?? "—")")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(drift.kind.label)
                    .font(.caption2.bold())
                    .foregroundStyle(drift.kind.color)
                if drift.kind != .contaminated, drift.after != nil, !drift.matchesExpectation {
                    Text("Fails expectation").font(.caption2.bold()).foregroundStyle(.red)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the spec and attribution")
    }
}

struct ProbeDetail: View {
    let drift: ProbeDrift

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(drift.probe.id) · \(drift.probe.title)").font(.headline)
                Text("Owner \(drift.probe.owner) · \(drift.probe.criticality.rawValue) · expects \(drift.probe.expected.description)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(drift.kind.label).font(.subheadline.bold()).foregroundStyle(drift.kind.color)
                Text("Attribution: \(drift.attribution.description)").font(.callout)
                Divider()
                Text(drift.probe.spec).font(.callout.monospaced())
                LintBadge(verdict: SpecLint.lint(drift.probe.spec))
            }
            .padding()
        }
    }
}

// MARK: - Lint

struct LintView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Sample.probes) { probe in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(probe.id).font(.caption.bold().monospaced()).foregroundStyle(.secondary)
                                Text(probe.title).font(.subheadline)
                            }
                            LintBadge(verdict: SpecLint.lint(probe.spec))
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Phrase matching, not judgement: it puts \"what are we actually building?\" into code review.")
                }
            }
            .navigationTitle("Spec lint")
        }
    }
}

struct LintBadge: View {
    let verdict: LintVerdict

    var body: some View {
        switch verdict {
        case .ready:
            Label("Ready: behaviour, constraints, acceptance", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case let .incomplete(missing):
            Label("Missing: \(missing.map(\.rawValue).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case let .rewrite(anchors):
            Label("Rewrite as behaviour · \(anchors.joined(separator: ", "))", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.caption).foregroundStyle(.red)
        }
    }
}
