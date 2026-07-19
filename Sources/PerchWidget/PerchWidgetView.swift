import SwiftUI
import WidgetKit

struct PerchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PerchWidgetEntry
    var familyOverride: WidgetFamily?

    init(entry: PerchWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !entry.isStale {
                switch familyOverride ?? family {
                case .systemExtraLarge: extraLarge(snapshot)
                case .systemLarge: large(snapshot)
                case .systemMedium: medium(snapshot)
                default: small(snapshot)
                }
            } else {
                unavailable
            }
        }
    }

    // MARK: - Families

    private func small(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            smallStatusStrip(snapshot)

            if let handoff = snapshot.waitingHandoffs.first {
                stateEyebrow(.waiting, text: snapshot.waitingCount == 1 ? "NEEDS YOU" : "NEXT OF \(snapshot.waitingCount)")
                Text(handoff.projectName)
                    .font(.headline)
                    .lineLimit(1)
                Text(handoff.action)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack {
                    duration(since: handoff.waitingSince, state: .waiting)
                    Spacer()
                    if handoff.focusURL != nil {
                        focusPill(compact: true, state: .waiting)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(headline(snapshot))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color(snapshot.dominantState))
                Text(summary(snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                freshness(snapshot.generatedAt)
            }
        }
        .widgetURL(singleFocusURL(snapshot))
    }

    private func medium(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                perchRail(snapshot, style: .compact)
                Text(headline(snapshot))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(snapshot.dominantState))
                    .monospacedDigit()
                    .fixedSize()
            }

            if snapshot.waitingHandoffs.isEmpty {
                calmState(snapshot, compact: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.waitingHandoffs.prefix(2).enumerated()), id: \.offset) { index, handoff in
                        handoffRow(handoff, size: .compact)
                        if index < min(snapshot.waitingHandoffs.count, 2) - 1 {
                            Divider().padding(.leading, 27)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            labelledCounts(snapshot, includesUncertain: true)
        }
    }

    private func large(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            perchRail(snapshot, style: .labelled)

            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.waitingCount > 0 ? "Attention" : "Agent activity")
                    .font(.headline)
                if snapshot.waitingCount > 0 {
                    countBadge(snapshot.waitingCount, state: .waiting)
                }
                Spacer()
            }

            if snapshot.waitingHandoffs.isEmpty {
                calmState(snapshot, compact: false)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.waitingHandoffs.prefix(4).enumerated()), id: \.offset) { index, handoff in
                        handoffRow(handoff, size: .regular)
                        if index < min(snapshot.waitingHandoffs.count, 4) - 1 {
                            Divider().padding(.leading, 31)
                        }
                    }
                }

                if snapshot.waitingCount > 4 {
                    Text("+ \(snapshot.waitingCount - 4) more waiting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            privacyFooter
        }
    }

    private func extraLarge(_ snapshot: PerchWidgetSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                perchRail(snapshot, style: .wide)
                Text(headline(snapshot))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color(snapshot.dominantState))
                    .fixedSize()
                freshness(snapshot.generatedAt)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FILTER")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 3)

                    filterRow(.all, label: "All sessions", count: snapshot.sessions.count, symbol: "square.stack.3d.up", state: nil)
                    filterRow(.waiting, label: "Waiting", count: snapshot.waitingCount, symbol: "bird.fill", state: .waiting)
                    filterRow(.working, label: "Working", count: snapshot.workingCount, symbol: "bird.fill", state: .working)
                    filterRow(.resting, label: "Resting", count: snapshot.restingCount, symbol: "bird.fill", state: .resting)
                    filterRow(.uncertain, label: "Uncertain", count: snapshot.uncertainCount, symbol: "questionmark.circle", state: .uncertain)

                    Spacer(minLength: 0)
                }
                .frame(width: 184, alignment: .leading)

                Divider()

                sessionPane(snapshot)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .contentTransition(.identity)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            privacyFooter
        }
        .animation(nil, value: entry.selectedFilter)
    }

    private func sessionPane(_ snapshot: PerchWidgetSnapshot) -> some View {
        let sessions = indexedSessions(snapshot)

        return VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(filterTitle(entry.selectedFilter))
                            .font(.headline)
                        countBadge(sessions.count, filter: entry.selectedFilter)
                        Spacer()
                    }
                    .padding(.bottom, 5)

                    Divider()

                    if sessions.isEmpty {
                        filteredEmptyState(entry.selectedFilter)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { index, item in
                                sessionRow(item.session)
                                if index < min(sessions.count, 5) - 1 {
                                    Divider().padding(.leading, 29)
                                }
                            }
                        }

                        if sessions.count > 5 {
                            Text("+ \(sessions.count - 5) more sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            .padding(.top, 5)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Signature rail

    private func smallStatusStrip(_ snapshot: PerchWidgetSnapshot) -> some View {
        HStack(spacing: 0) {
            smallStatusCount(snapshot.waitingCount, state: .waiting)
            Spacer(minLength: 3)
            smallStatusCount(snapshot.workingCount, state: .working)
            Spacer(minLength: 3)
            smallStatusCount(snapshot.restingCount, state: .resting)
            Spacer(minLength: 3)
            smallStatusCount(snapshot.uncertainCount, state: .uncertain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stateSummary(snapshot))
    }

    private func smallStatusCount(_ count: Int, state: PerchWidgetSnapshot.State) -> some View {
        HStack(spacing: 2) {
            stateGlyph(state, size: 10)
                .frame(width: 13)
            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(count == 0 ? Color.secondary.opacity(0.65) : color(state))
        }
    }

    private enum PerchRailStyle { case compact, labelled, wide }

    private func perchRail(_ snapshot: PerchWidgetSnapshot, style: PerchRailStyle) -> some View {
        let showsLabels = style == .labelled
        return VStack(spacing: showsLabels ? 7 : 4) {
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(style == .compact ? 0.38 : 0.52))
                    .frame(height: 1)
                    .padding(.horizontal, 5)

                HStack(spacing: 14) {
                    railFlock(count: snapshot.waitingCount, state: .waiting)
                    railFlock(count: snapshot.workingCount, state: .working)
                    Spacer(minLength: 4)
                    railFlock(count: snapshot.restingCount, state: .resting)
                    railFlock(count: snapshot.uncertainCount, state: .uncertain)
                }
                .padding(.horizontal, 10)
            }
            .frame(height: style == .compact ? 19 : 24)

            if showsLabels {
                labelledCounts(snapshot, includesUncertain: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stateSummary(snapshot))
    }

    @ViewBuilder
    private func railFlock(count: Int, state: PerchWidgetSnapshot.State) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                stateGlyph(state, size: state == .waiting ? 17 : 15)
                if count > 1 {
                    Text("×\(count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(state == .waiting ? color(state) : .secondary)
                }
            }
            .padding(.horizontal, 4)
            .background(.background)
        }
    }

    // MARK: - Rows

    private enum HandoffRowSize { case compact, regular }

    @ViewBuilder
    private func handoffRow(_ handoff: PerchWidgetSnapshot.WaitingHandoff, size: HandoffRowSize) -> some View {
        if let url = handoff.focusURL {
            Link(destination: url) {
                handoffRowContent(handoff, size: size, showsFocus: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus \(handoff.projectName), \(handoff.action), \(handoff.providerName)")
        } else {
            handoffRowContent(handoff, size: size, showsFocus: false)
                .accessibilityLabel("\(handoff.projectName), \(handoff.action), \(handoff.providerName), focus unavailable")
        }
    }

    private func handoffRowContent(
        _ handoff: PerchWidgetSnapshot.WaitingHandoff,
        size: HandoffRowSize,
        showsFocus: Bool
    ) -> some View {
        HStack(spacing: size == .regular ? 11 : 9) {
            stateGlyph(.waiting, size: size == .regular ? 15 : 13)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(handoff.projectName)
                    .font(size == .regular ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(handoff.action) · \(handoff.providerName)")
                    .font(size == .regular ? .caption : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 5)
            duration(since: handoff.waitingSince, state: .waiting)

            if showsFocus {
                focusPill(compact: size == .compact, state: .waiting)
            }
        }
        .frame(minHeight: size == .regular ? 44 : 35)
        .padding(.horizontal, size == .regular ? 8 : 5)
        .background(color(.waiting).opacity(0.075), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sessionRow(_ session: PerchWidgetSnapshot.SessionSummary) -> some View {
        if let url = session.focusURL {
            Link(destination: url) {
                sessionRowContent(session, showsFocus: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus \(session.projectName), \(session.detail), \(session.providerName)")
        } else {
            sessionRowContent(session, showsFocus: false)
                .accessibilityLabel("\(session.projectName), \(session.detail), \(session.providerName), focus unavailable")
        }
    }

    private func sessionRowContent(_ session: PerchWidgetSnapshot.SessionSummary, showsFocus: Bool) -> some View {
        HStack(spacing: 9) {
            stateGlyph(session.state, size: 13)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(session.detail) · \(session.providerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let date = session.activityAt {
                duration(since: date, state: session.state)
                    .frame(width: 76, alignment: .trailing)
            }

            if showsFocus {
                focusPill(compact: session.state != .waiting, state: session.state)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 7)
        .background(
            session.state == .waiting ? color(.waiting).opacity(0.075) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Filters and summaries

    private func filterRow(
        _ filter: PerchWidgetFilter,
        label: String,
        count: Int,
        symbol: String,
        state: PerchWidgetSnapshot.State?
    ) -> some View {
        Button(intent: SetPerchWidgetFilterIntent(filter: filter)) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(entry.selectedFilter == filter ? filterAccent(filter) : .clear)
                    .frame(width: 3, height: 19)
                Image(systemName: symbol)
                    .font(.caption.weight(.medium))
                    .frame(width: 16)
                    .foregroundStyle(state.map(color) ?? .secondary)
                Text(label)
                    .font(.subheadline.weight(entry.selectedFilter == filter ? .semibold : .regular))
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(entry.selectedFilter == filter ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(label.lowercased()), \(count)")
        .accessibilityAddTraits(entry.selectedFilter == filter ? .isSelected : [])
    }

    private func calmState(_ snapshot: PerchWidgetSnapshot, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: snapshot.workingCount > 0 ? "bird.fill" : "bird")
                .font(compact ? .title3 : .title2)
                .foregroundStyle(color(snapshot.dominantState))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.workingCount > 0 ? "Working quietly" : "Nothing needs you")
                    .font(.headline)
                Text(summary(snapshot))
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, compact ? 1 : 5)
        .accessibilityElement(children: .combine)
    }

    private func stateEyebrow(_ state: PerchWidgetSnapshot.State, text: String) -> some View {
        HStack(spacing: 5) {
            stateDot(state)
            Text(text)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .foregroundStyle(color(state))
    }

    private func labelledCounts(_ snapshot: PerchWidgetSnapshot, includesUncertain: Bool) -> some View {
        HStack(spacing: 11) {
            countLabel("wait", count: snapshot.waitingCount, state: .waiting)
            countLabel("work", count: snapshot.workingCount, state: .working)
            countLabel("rest", count: snapshot.restingCount, state: .resting)
            if includesUncertain, snapshot.uncertainCount > 0 {
                countLabel("uncertain", count: snapshot.uncertainCount, state: .uncertain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stateSummary(snapshot))
    }

    private func countLabel(_ label: String, count: Int, state: PerchWidgetSnapshot.State) -> some View {
        HStack(spacing: 3) {
            stateDot(state)
            Text("\(count) \(label)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stateGlyph(_ state: PerchWidgetSnapshot.State, size: CGFloat) -> some View {
        switch state {
        case .waiting:
            Image(systemName: "bird.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color(state))
                .accessibilityHidden(true)
        case .working:
            Image(systemName: "bird.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color(state))
                .accessibilityHidden(true)
        case .resting:
            Image(systemName: "bird.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(color(state))
                .accessibilityHidden(true)
        case .uncertain:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "bird")
                    .font(.system(size: size, weight: .regular))
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: max(7, size * 0.48), weight: .bold))
                    .background(.background, in: Circle())
                    .offset(x: 2, y: 1)
            }
            .foregroundStyle(color(state))
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func stateDot(_ state: PerchWidgetSnapshot.State) -> some View {
        if state == .uncertain {
            Circle()
                .stroke(color(state), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(color(state))
                .frame(width: 7, height: 7)
        }
    }

    private func focusPill(compact: Bool, state: PerchWidgetSnapshot.State) -> some View {
        HStack(spacing: 4) {
            if !compact {
                Text("Focus")
            }
            Image(systemName: "arrow.up.forward.app")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(state == .uncertain ? Color.secondary : color(state))
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: 24)
        .background(
            (state == .uncertain ? Color.secondary : color(state)).opacity(0.12),
            in: Capsule()
        )
        .accessibilityHidden(true)
    }

    private func countBadge(_ count: Int, state: PerchWidgetSnapshot.State) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color(state))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color(state).opacity(0.12), in: Capsule())
    }

    private func countBadge(_ count: Int, filter: PerchWidgetFilter) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(filterColor(filter))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(filterColor(filter).opacity(0.10), in: Capsule())
    }

    private func duration(since date: Date, state: PerchWidgetSnapshot.State) -> some View {
        Text(date, style: state == .waiting ? .timer : .relative)
            .font(.caption.monospacedDigit())
            .foregroundStyle(state == .waiting ? color(.waiting) : .secondary)
    }

    private var privacyFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock")
            Text("Local observation only")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func filteredEmptyState(_ filter: PerchWidgetFilter) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: filter == .all ? "tray" : "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(filter == .all ? "No sessions observed" : "No matching sessions")
                    .font(.headline)
                Text(filter == .all ? "Perch will show local activity here." : "Choose another state to change the filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 10)
        Spacer(minLength: 0)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "bird")
                    .foregroundStyle(.secondary)
                Text("Perch").font(.headline)
            }
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

    // MARK: - Values

    private struct IndexedSession: Identifiable {
        let id: Int
        let session: PerchWidgetSnapshot.SessionSummary
    }

    private func indexedSessions(_ snapshot: PerchWidgetSnapshot) -> [IndexedSession] {
        snapshot.sessions.enumerated().compactMap { index, session in
            guard entry.selectedFilter == .all || session.state.rawValue == entry.selectedFilter.rawValue else {
                return nil
            }
            return IndexedSession(id: index, session: session)
        }
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

    private func filterAccent(_ filter: PerchWidgetFilter) -> Color {
        switch filter {
        case .waiting: color(.waiting)
        case .working: color(.working)
        case .resting, .uncertain, .all: .secondary
        }
    }

    private func filterColor(_ filter: PerchWidgetFilter) -> Color {
        switch filter {
        case .waiting: color(.waiting)
        case .working: color(.working)
        case .resting, .uncertain, .all: .secondary
        }
    }

    private func freshness(_ date: Date) -> some View {
        Text(date, style: .relative)
            .font(.caption2)
            .foregroundStyle(.secondary)
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

    private func stateSummary(_ snapshot: PerchWidgetSnapshot) -> String {
        "\(snapshot.waitingCount) waiting, \(snapshot.workingCount) working, " +
        "\(snapshot.restingCount) resting, \(snapshot.uncertainCount) uncertain"
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
