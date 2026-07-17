import SwiftUI

struct DesktopPerchView: View {
    let roster: RosterCoordinator
    let hide: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var presentation: AttentionPresentation {
        AttentionPresentation(sessions: roster.sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchDesign.Space.section) {
            header
            AttentionOverviewView(
                presentation: presentation,
                mode: .attention,
                showsModeControl: false
            )
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(PerchDesign.Space.panel)
        .frame(width: 336, height: 272)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: PerchDesign.Shape.companionRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: PerchDesign.Shape.companionRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PerchDesign.Shape.companionRadius, style: .continuous)
                .stroke(PerchDesign.ColorRole.separator)
        }
        .contentShape(RoundedRectangle(cornerRadius: PerchDesign.Shape.companionRadius, style: .continuous))
    }

    private var header: some View {
        PerchSurfaceHeader(presentation: presentation) {
            Button(action: hide) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide Desktop Perch")
            .accessibilityLabel("Hide Desktop Perch")
        }
    }

    @ViewBuilder
    private var content: some View {
        if presentation.waitingSessions.isEmpty {
            HStack(spacing: PerchDesign.Space.row) {
                Image(systemName: differentiateWithoutColor ? "checkmark.circle" : "bird")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing needs you")
                        .font(.body.weight(.medium))
                    Text(calmDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(presentation.waitingSessions.prefix(3))) { item in
                    WaitingHandoffRowView(item: item, density: .compact) {
                        Task { try? await roster.focus(item.session) }
                    }
                    if item.id != presentation.waitingSessions.prefix(3).last?.id {
                        Divider().padding(.leading, 22)
                    }
                }
                if presentation.waitingCount > 3 {
                    Text("+\(presentation.waitingCount - 3) more in the menu-bar panel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Local observation only", systemImage: "lock")
            Spacer()
            Text("Drag to move")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var calmDetail: String {
        if presentation.observedCount == 0 { return "Watching enabled providers" }
        if presentation.workingCount > 0 { return "\(presentation.workingCount) working quietly" }
        if presentation.restingCount > 0 { return "All observed agents are resting" }
        return "Observed state is uncertain"
    }

}
