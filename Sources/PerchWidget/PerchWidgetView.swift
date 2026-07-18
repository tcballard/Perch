import SwiftUI
import WidgetKit

struct PerchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PerchWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !entry.isStale {
                switch family {
                case .systemExtraLarge:
                    extraLarge(snapshot)
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

    private func extraLarge(_ snapshot: PerchWidgetSnapshot) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    header(snapshot.dominantState)
                    Spacer()
                    freshness(snapshot.generatedAt)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Sessions")
                        .font(.title3.weight(.semibold))
                    Text("Filter observed activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    filterRow(.all, label: "All sessions", count: snapshot.sessions.count, symbol: "tray.full", state: nil)
                    filterRow(.waiting, label: "Waiting", count: snapshot.waitingCount, symbol: "bird.fill", state: .waiting)
                    filterRow(.working, label: "Working", count: snapshot.workingCount, symbol: "bird.fill", state: .working)
                    filterRow(.resting, label: "Resting", count: snapshot.restingCount, symbol: "bird", state: .resting)
                    filterRow(.uncertain, label: "Uncertain", count: snapshot.uncertainCount, symbol: "bird", state: .uncertain)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Image(systemName: "lock")
                    Text("Local observation only")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .combine)
            }
            .padding(.trailing, 22)
            .frame(width: 250, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(filterTitle(entry.selectedFilter))
                        .font(.title3.weight(.semibold))
                    Text("\(filteredSessions(snapshot).count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(filterColor(entry.selectedFilter))
                    Spacer()
                    Text("Observed sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                let sessions = filteredSessions(snapshot)
                if sessions.isEmpty {
                    filteredEmptyState(entry.selectedFilter)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.prefix(8).enumerated()), id: \.offset) { index, session in
                            sessionRow(session)
                            if index < min(sessions.count, 8) - 1 {
                                Divider()
                                    .padding(.leading, 34)
                            }
                        }
                    }

                    if sessions.count > 8 {
                        Text("+ \(sessions.count - 8) more sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                HStack {
                    Text("No session content stored")
                    Spacer()
                    Text(headline(snapshot))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.leading, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filterRow(
        _ filter: PerchWidgetFilter,
        label: String,
        count: Int,
        symbol: String,
        state: PerchWidgetSnapshot.State?
    ) -> some View {
        Button(intent: SetPerchWidgetFilterIntent(filter: filter)) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(state.map(color) ?? .secondary)
                Text(label)
                    .font(.subheadline.weight(entry.selectedFilter == filter ? .semibold : .regular))
                Spacer()
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(entry.selectedFilter == filter ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(label.lowercased()), \(count)")
        .accessibilityAddTraits(entry.selectedFilter == filter ? .isSelected : [])
    }

    private func filteredSessions(_ snapshot: PerchWidgetSnapshot) -> [PerchWidgetSnapshot.SessionSummary] {
        guard entry.selectedFilter != .all else { return snapshot.sessions }
        return snapshot.sessions.filter { $0.state.rawValue == entry.selectedFilter.rawValue }
    }

    private func filterTitle(_ filter: PerchWidgetFilter) -> String {
        switch filter {
        case .all: "All sessions"
        case .waiting: "Waiting"
        case .working: "Working"
        case .resting: "Resting"
        case .uncertain: "Uncertain"
        }
    }

    private func filterColor(_ filter: PerchWidgetFilter) -> Color {
        switch filter {
        case .waiting: color(.waiting)
        case .working: color(.working)
        case .resting, .uncertain, .all: .secondary
        }
    }

    @ViewBuilder
    private func filteredEmptyState(_ filter: PerchWidgetFilter) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: filter == .all ? "tray" : "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(filter == .all ? "No sessions observed" : "No matching sessions")
                    .font(.headline)
                Text(filter == .all ? "Perch will show local activity here." : "Choose another state to change the filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        Spacer(minLength: 0)
    }

    private func sessionRow(_ session: PerchWidgetSnapshot.SessionSummary) -> some View {
        HStack(spacing: 11) {
            Image(systemName: session.state == .uncertain ? "bird" : "bird.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(color(session.state))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(session.detail) · \(session.providerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let date = session.activityAt {
                Text(date, style: session.state == .waiting ? .timer : .relative)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        session.state == .waiting
                            ? color(.waiting)
                            : Color.secondary.opacity(0.65)
                    )
            }

            if let url = session.focusURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.app")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus \(session.projectName)")
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
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
