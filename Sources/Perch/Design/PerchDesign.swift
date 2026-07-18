import SwiftUI

enum PerchDesign {
    enum ColorRole {
        static let attention = Color.orange
        static let working = Color.blue
        static let resting = Color.secondary
        static let uncertain = Color.secondary
        static let separator = Color.primary.opacity(0.10)
        static let subtleSurface = Color.primary.opacity(0.035)
    }

    enum Space {
        static let compact: CGFloat = 6
        static let row: CGFloat = 10
        static let section: CGFloat = 12
        static let panel: CGFloat = 14
    }

    enum Shape {
        static let groupRadius: CGFloat = 12
        static let attentionRadius: CGFloat = 8
        static let companionRadius: CGFloat = 20
    }

    enum Symbol {
        static let perchBird = Font.system(size: 17, weight: .medium)
        static let headerBird = Font.system(size: 22, weight: .semibold)
    }
}

extension PerchDesign.ColorRole {
    static func state(_ state: AgentState) -> Color {
        switch state {
        case .waiting: attention
        case .working: working
        case .idle, .done: resting
        case .unknown: uncertain
        }
    }
}

struct PerchSurfaceHeader<Trailing: View>: View {
    let presentation: AttentionPresentation
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: PerchDesign.Space.row) {
            Image(systemName: presentation.dominantState == .unknown ? "bird" : "bird.fill")
                .font(PerchDesign.Symbol.headerBird)
                .foregroundStyle(PerchDesign.ColorRole.state(presentation.dominantState))
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Perch")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(presentation.waitingCount > 0 ? PerchDesign.ColorRole.attention : .secondary)
                    .monospacedDigit()
            }
            Spacer()
            trailing()
        }
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        presentation.waitingCount == 0 ? "Nothing needs you" : "\(presentation.waitingCount) need you"
    }
}

struct PerchOverviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
