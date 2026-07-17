import SwiftUI
import WidgetKit

struct PerchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PerchWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !entry.isStale {
                switch family {
                case .systemLarge:
                    large(snapshot)
                case .systemMedium:
                    medium(snapshot)
                default:
                    small(snapshot)
                }
            } else {
                unavailable
            }
        }
    }

    private func small(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(snapshot.dominantState)

            Spacer(minLength: 0)

            Text(headline(snapshot))
                .font(.title3.weight(.semibold))
                .foregroundStyle(color(snapshot.dominantState))
                .minimumScaleFactor(0.75)

            Text(summary(snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            freshness(snapshot.generatedAt)
        }
        .widgetURL(singleFocusURL(snapshot))
    }

    private func medium(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                header(snapshot.dominantState)
                Spacer()
                Text(headline(snapshot))
                    .font(.headline)
                    .foregroundStyle(color(snapshot.dominantState))
            }

            Divider()

            if snapshot.waitingHandoffs.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.workingCount > 0 ? "bird.fill" : "bird")
                        .font(.title2)
                        .foregroundStyle(color(snapshot.dominantState))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.workingCount > 0 ? "Working quietly" : "Nothing needs you")
                            .font(.headline)
                        Text(summary(snapshot))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(snapshot.waitingHandoffs.prefix(2).enumerated()), id: \.offset) { _, handoff in
                        handoffRow(handoff)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack {
                counts(snapshot)
                Spacer()
                freshness(snapshot.generatedAt)
            }
        }
    }

    private func large(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                header(snapshot.dominantState)
                Spacer()
                Text(headline(snapshot))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color(snapshot.dominantState))
            }

            Divider()

            stateRail(snapshot)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Attention")
                    .font(.headline)
                if snapshot.waitingCount > 0 {
                    Text("\(snapshot.waitingCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                Spacer()
                freshness(snapshot.generatedAt)
            }

            if snapshot.waitingHandoffs.isEmpty {
                largeEmptyState(snapshot)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.waitingHandoffs.prefix(3).enumerated()), id: \.offset) { index, handoff in
                        largeHandoffRow(handoff)
                        if index < min(snapshot.waitingHandoffs.count, 3) - 1 {
                            Divider()
                                .padding(.leading, 25)
                        }
                    }
                }

                if snapshot.waitingCount > snapshot.waitingHandoffs.count {
                    Text("+ \(snapshot.waitingCount - snapshot.waitingHandoffs.count) more waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 5) {
                Image(systemName: "lock")
                Text("Local observation only")
                Spacer()
                Text("No session content stored")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .combine)
        }
    }

    private func stateRail(_ snapshot: PerchWidgetSnapshot) -> some View {
        HStack(spacing: 0) {
            stateMetric("Waiting", count: snapshot.waitingCount, state: .waiting, symbol: "bird.fill")
            stateMetric("Working", count: snapshot.workingCount, state: .working, symbol: "bird.fill")
            stateMetric("Resting", count: snapshot.restingCount, state: .resting, symbol: "bird")
            stateMetric("Uncertain", count: snapshot.uncertainCount, state: .uncertain, symbol: "bird")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(snapshot.waitingCount) waiting, \(snapshot.workingCount) working, " +
            "\(snapshot.restingCount) resting, \(snapshot.uncertainCount) uncertain"
        )
    }

    private func stateMetric(
        _ label: String,
        count: Int,
        state: PerchWidgetSnapshot.State,
        symbol: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(color(state))
                Text("\(count)")
                    .font(.headline.monospacedDigit())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func largeEmptyState(_ snapshot: PerchWidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: snapshot.workingCount > 0 ? "bird.fill" : "bird")
                .font(.title2)
                .foregroundStyle(color(snapshot.dominantState))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.workingCount > 0 ? "Working quietly" : "Nothing needs you")
                    .font(.headline)
                Text(summary(snapshot))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)

        Spacer(minLength: 0)
    }

    private func largeHandoffRow(_ handoff: PerchWidgetSnapshot.WaitingHandoff) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.orange)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(handoff.projectName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(handoff.action) · \(handoff.providerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(handoff.waitingSince, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.orange)

            if let url = handoff.focusURL {
                Link(destination: url) {
                    Label("Focus", systemImage: "arrow.up.forward.app")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Focus \(handoff.projectName)")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func header(_ state: PerchWidgetSnapshot.State) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bird.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color(state))
            Text("Perch")
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }

    private func handoffRow(_ handoff: PerchWidgetSnapshot.WaitingHandoff) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(handoff.projectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(handoff.action) · \(handoff.providerName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(handoff.waitingSince, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.orange)

            if let url = handoff.focusURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.app")
                        .accessibilityLabel("Focus \(handoff.projectName)")
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(.uncertain)
            Spacer()
            Image(systemName: "bird")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Status uncertain")
                .font(.headline)
            Text("Perch has not published a recent local snapshot.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func counts(_ snapshot: PerchWidgetSnapshot) -> some View {
        HStack(spacing: 10) {
            Label("\(snapshot.waitingCount)", systemImage: "circle.fill")
                .foregroundStyle(.orange)
            Label("\(snapshot.workingCount)", systemImage: "circle.fill")
                .foregroundStyle(.blue)
            Label("\(snapshot.restingCount)", systemImage: "circle.fill")
                .foregroundStyle(.secondary)
            if snapshot.uncertainCount > 0 {
                Label("\(snapshot.uncertainCount)", systemImage: "circle.dotted")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.monospacedDigit())
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(
            "\(snapshot.waitingCount) waiting, \(snapshot.workingCount) working, " +
            "\(snapshot.restingCount) resting, \(snapshot.uncertainCount) uncertain"
        )
    }

    private func freshness(_ date: Date) -> some View {
        Text(date, style: .relative)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Updated \(date.formatted(.relative(presentation: .named)))")
    }

    private func headline(_ snapshot: PerchWidgetSnapshot) -> String {
        if snapshot.waitingCount > 0 {
            return snapshot.waitingCount == 1 ? "1 needs you" : "\(snapshot.waitingCount) need you"
        }
        if snapshot.workingCount > 0 { return "Working" }
        if snapshot.restingCount > 0 { return "All clear" }
        return "Uncertain"
    }

    private func summary(_ snapshot: PerchWidgetSnapshot) -> String {
        if snapshot.waitingCount > 0 {
            return snapshot.waitingHandoffs.first?.action ?? "Attention required"
        }
        if snapshot.workingCount > 0 {
            return "\(snapshot.workingCount) " + (snapshot.workingCount == 1 ? "agent is active" : "agents are active")
        }
        if snapshot.uncertainCount > 0 {
            return "\(snapshot.uncertainCount) " + (snapshot.uncertainCount == 1 ? "agent is uncertain" : "agents are uncertain")
        }
        return "No local agent needs attention"
    }

    private func singleFocusURL(_ snapshot: PerchWidgetSnapshot) -> URL? {
        guard snapshot.waitingCount == 1 else { return nil }
        return snapshot.waitingHandoffs.first?.focusURL
    }

    private func color(_ state: PerchWidgetSnapshot.State) -> Color {
        switch state {
        case .waiting: .orange
        case .working: .blue
        case .resting: .secondary
        case .uncertain: .secondary
        }
    }
}
