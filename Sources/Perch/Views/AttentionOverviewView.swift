import SwiftUI

struct AttentionOverviewView: View {
    let presentation: AttentionPresentation

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bird.fill")
                    .font(.title3)
                    .foregroundStyle(presentation.waitingCount > 0 ? .orange : .secondary)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)

                if presentation.usesAggregatedOverview {
                    aggregateMarks
                } else {
                    individualMarks
                }
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var individualMarks: some View {
        HStack(spacing: 6) {
            ForEach(presentation.allSessions) { item in
                Circle()
                    .fill(color(for: item))
                    .frame(width: item.session.state == .waiting ? 10 : 7, height: item.session.state == .waiting ? 10 : 7)
            }
        }
    }

    private var aggregateMarks: some View {
        HStack(spacing: 7) {
            countMark(presentation.waitingCount, color: .orange)
            countMark(presentation.workingCount, color: .blue)
            countMark(presentation.restingCount, color: .secondary)
            countMark(presentation.uncertainCount, color: .gray)
        }
    }

    private func countMark(_ count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func color(for item: SessionPresentation) -> Color {
        if item.isUncertain { return .gray.opacity(0.55) }
        switch item.session.state {
        case .waiting: return .orange
        case .working: return .blue
        case .idle, .done: return .secondary.opacity(0.55)
        case .unknown: return .gray.opacity(0.55)
        }
    }

    private var summary: String {
        if presentation.observedCount == 0 { return "No agents observed yet" }
        if presentation.waitingCount == 0 { return "Nothing needs you · \(presentation.observedCount) observed" }
        return "\(presentation.waitingCount) waiting · \(presentation.observedCount) observed"
    }
}
