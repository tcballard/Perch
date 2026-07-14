import SwiftUI

struct SessionRowView: View {
    let session: AgentSession
    let focus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.label ?? "Untitled session")
                        .fontWeight(session.state == .waiting ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    Text(session.provider.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if session.state == .waiting, let waitingSince = session.waitingSince {
                    Text(waitingSince, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Button(action: focus) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .disabled(session.nativeSurface == nil)
            .help(session.nativeSurface == nil ? "Focus unavailable" : "Focus session")
            .accessibilityLabel(session.nativeSurface == nil ? "Focus unavailable" : "Focus session")
        }
        .padding(10)
        .background(session.state == .waiting ? Color.orange.opacity(0.10) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        if let waitingOn = session.waitingOn { return waitingOn }
        return "\(session.state.rawValue.capitalized) · \(session.confidence.rawValue)"
    }

    private var stateColor: Color {
        switch session.state {
        case .waiting: .orange
        case .working: .blue
        case .idle, .done: .secondary
        case .unknown: .gray
        }
    }
}
