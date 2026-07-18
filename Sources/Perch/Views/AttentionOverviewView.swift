import SwiftUI

struct AttentionOverviewView: View {
    let presentation: AttentionPresentation
    let mode: PanelMode
    let isHovered: Bool
    let isKeyboardFocused: Bool
    let showsModeControl: Bool
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        presentation: AttentionPresentation,
        mode: PanelMode,
        isHovered: Bool = false,
        isKeyboardFocused: Bool = false,
        showsModeControl: Bool = true
    ) {
        self.presentation = presentation
        self.mode = mode
        self.isHovered = isHovered
        self.isKeyboardFocused = isKeyboardFocused
        self.showsModeControl = showsModeControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchDesign.Space.row) {
            ZStack(alignment: .bottom) {
                perchLine
                if presentation.usesAggregatedOverview {
                    aggregateBirds
                } else {
                    individualBirds
                }
            }
            .frame(height: 42)

            ViewThatFits(in: .horizontal) {
                stateLegend(compact: false)
                stateLegend(compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text(summaryStatus)
                    .monospacedDigit()
                Spacer()
                if showsModeControl {
                    Label(mode == .attention ? "Show all activity" : "Show attention", systemImage: "arrow.left.arrow.right")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(PerchDesign.Space.section)
        .background(isHovered && showsModeControl ? Color.primary.opacity(0.055) : PerchDesign.ColorRole.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: PerchDesign.Shape.groupRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PerchDesign.Shape.groupRadius, style: .continuous)
                .stroke(
                    isKeyboardFocused && showsModeControl ? Color.accentColor : PerchDesign.ColorRole.separator,
                    lineWidth: isKeyboardFocused || contrast == .increased ? 1.5 : 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func stateLegend(compact: Bool) -> some View {
        HStack(spacing: compact ? PerchDesign.Space.compact : PerchDesign.Space.row) {
            stateCount(presentation.waitingCount, title: compact ? "wait" : "waiting", symbol: "exclamationmark", color: PerchDesign.ColorRole.attention)
            stateCount(presentation.workingCount, title: compact ? "work" : "working", symbol: "bolt.fill", color: PerchDesign.ColorRole.working)
            stateCount(presentation.restingCount, title: compact ? "rest" : "resting", symbol: "pause.fill", color: PerchDesign.ColorRole.resting)
            stateCount(presentation.uncertainCount, title: compact ? "unknown" : "uncertain", symbol: "questionmark", color: PerchDesign.ColorRole.uncertain)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var perchLine: some View {
        Capsule(style: .continuous)
            .fill(.secondary)
            .frame(height: contrast == .increased ? 2 : 1)
            .padding(.horizontal, 8)
        .padding(.bottom, 5)
    }

    private var individualBirds: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(presentation.allSessions) { item in
                bird(for: item)
            }
        }
        .padding(.bottom, 7)
    }

    private var aggregateBirds: some View {
        HStack(alignment: .bottom, spacing: 10) {
            aggregateBird(count: presentation.waitingCount, state: .waiting)
            aggregateBird(count: presentation.workingCount, state: .working)
            aggregateBird(count: presentation.restingCount, state: .idle)
            aggregateBird(count: presentation.uncertainCount, state: .unknown)
        }
        .padding(.bottom, 7)
    }

    private func bird(for item: SessionPresentation) -> some View {
        Image(systemName: item.isUncertain ? "bird" : "bird.fill")
            .font(PerchDesign.Symbol.perchBird)
            .foregroundStyle(color(for: item))
            .frame(width: 24, height: 26)
            .background {
                if item.presentedState == .waiting {
                    RoundedRectangle(cornerRadius: PerchDesign.Shape.attentionRadius, style: .continuous)
                        .stroke(PerchDesign.ColorRole.attention, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
    }

    @ViewBuilder
    private func aggregateBird(count: Int, state: AgentState) -> some View {
        if count > 0 {
            HStack(alignment: .bottom, spacing: 2) {
                Image(systemName: state == .unknown ? "bird" : "bird.fill")
                    .font(PerchDesign.Symbol.perchBird)
                    .foregroundStyle(color(for: state))
                Text("×\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stateCount(_ count: Int, title: String, symbol: String, color: Color) -> some View {
        Label {
            Text("\(count) \(title)")
                .monospacedDigit()
        } icon: {
            Image(systemName: differentiateWithoutColor ? symbol : "circle.fill")
                .foregroundStyle(color)
        }
        .font(.caption2)
        .foregroundStyle(count == 0 ? .tertiary : .secondary)
    }

    private func color(for item: SessionPresentation) -> Color {
        if item.isUncertain { return PerchDesign.ColorRole.uncertain }
        return color(for: item.session.state)
    }

    private func color(for state: AgentState) -> Color {
        switch state {
        case .waiting: PerchDesign.ColorRole.attention
        case .working: PerchDesign.ColorRole.working
        case .idle, .done: PerchDesign.ColorRole.resting
        case .unknown: PerchDesign.ColorRole.uncertain
        }
    }

    private var summary: String {
        if presentation.observedCount == 0 { return "No agents observed yet" }
        if presentation.waitingCount == 0 { return "Nothing needs you · \(presentation.observedCount) observed" }
        return "\(presentation.waitingCount) waiting · \(presentation.observedCount) observed"
    }

    private var summaryStatus: String {
        if presentation.waitingCount > 0 { return "\(presentation.waitingCount) need you" }
        if presentation.workingCount > 0 { return "\(presentation.workingCount) working" }
        if presentation.restingCount > 0 { return "All resting" }
        return presentation.observedCount == 0 ? "Watching providers" : "State uncertain"
    }
}
