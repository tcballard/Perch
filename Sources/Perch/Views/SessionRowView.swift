import SwiftUI

struct SessionRowView: View {
    let item: SessionPresentation
    let focus: () -> Void

    private var session: AgentSession { item.session }

    var body: some View {
        HStack(alignment: .center, spacing: PerchDesign.Space.row) {
            Image(systemName: stateSymbol)
                .font(.caption)
                .foregroundStyle(stateColor)
                .frame(width: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.projectName)
                    .fontWeight(item.presentedState == .waiting ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    Text(item.providerName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            }

            if item.canFocus {
                Button("Focus", action: focus)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Focus \(item.projectName)")
            } else {
                Text("Focus unavailable")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, PerchDesign.Space.compact)
        .padding(.vertical, PerchDesign.Space.row)
        .accessibilityElement(children: .contain)
    }

    private var detailText: String {
        if item.presentedState == .waiting {
            return item.waitingAction?.rawValue ?? WaitingAction.input.rawValue
        }
        return "\(item.presentedState.rawValue.capitalized) · \(session.confidence.rawValue)"
    }

    private var stateColor: Color {
        PerchDesign.ColorRole.state(item.presentedState)
    }

    private var stateSymbol: String {
        switch item.presentedState {
        case .waiting: "exclamationmark.circle.fill"
        case .working: "bolt.fill"
        case .idle, .done: "pause.fill"
        case .unknown: "questionmark.circle"
        }
    }
}
