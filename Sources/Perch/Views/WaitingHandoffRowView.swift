import SwiftUI

struct WaitingHandoffRowView: View {
    let item: SessionPresentation
    let focus: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        HStack(alignment: .center, spacing: PerchDesign.Space.row) {
            Image(systemName: differentiateWithoutColor ? "exclamationmark.circle.fill" : "circle.fill")
                .font(.caption)
                .foregroundStyle(PerchDesign.ColorRole.attention)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.projectName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(item.waitingAction?.rawValue ?? WaitingAction.input.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    if let waitingSince = item.session.waitingSince {
                        Label {
                            Text(waitingSince, style: .relative)
                        } icon: {
                            Image(systemName: "clock")
                        }
                    }
                    Text("·")
                    Text(item.providerName)
                    Text("·")
                    Text(item.session.confidence.rawValue)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer(minLength: 8)

            if item.canFocus {
                Button("Focus", action: focus)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Focus \(item.projectName)")
                    .accessibilityLabel("Focus \(item.projectName)")
            } else {
                Label("Focus unavailable", systemImage: "nosign")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .labelStyle(.titleAndIcon)
                    .help("This provider does not support focus")
            }
        }
        .padding(.horizontal, PerchDesign.Space.compact)
        .padding(.vertical, PerchDesign.Space.row)
        .accessibilityElement(children: .contain)
    }
}
