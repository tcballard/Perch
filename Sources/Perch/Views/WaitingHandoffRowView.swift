import SwiftUI

struct WaitingHandoffRowView: View {
    let item: SessionPresentation
    let focus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.projectName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(item.waitingAction?.rawValue ?? WaitingAction.input.rawValue)
                    .font(.caption)
                HStack(spacing: 5) {
                    Text(item.providerName)
                    Text("·")
                    Text(item.session.confidence.rawValue)
                    if let waitingSince = item.session.waitingSince {
                        Text("·")
                        Text(waitingSince, style: .relative)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: focus) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .disabled(!item.canFocus)
            .help(item.canFocus ? "Focus \(item.projectName)" : "Focus unavailable")
            .accessibilityLabel(item.canFocus ? "Focus \(item.projectName)" : "Focus unavailable for \(item.projectName)")
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
