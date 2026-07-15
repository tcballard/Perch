import AppKit
import SwiftUI

struct PerchPanelView: View {
    let roster: RosterCoordinator
    @State private var mode: PanelMode = .attention
    @State private var isPerchHovered = false
    @FocusState private var isPerchFocused: Bool

    private var presentation: AttentionPresentation {
        AttentionPresentation(sessions: roster.sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Button {
                mode = mode == .attention ? .allActivity : .attention
            } label: {
                AttentionOverviewView(
                    presentation: presentation,
                    mode: mode,
                    isHovered: isPerchHovered,
                    isKeyboardFocused: isPerchFocused
                )
            }
                .buttonStyle(PerchOverviewButtonStyle())
                .focused($isPerchFocused)
                .onHover { isPerchHovered = $0 }
                .help(mode == .attention ? "Show all activity" : "Show attention")
                .accessibilityLabel(mode == .attention ? "Show all activity" : "Show attention")
                .accessibilityHint("Switches the session list below")
                .padding(.horizontal, PerchDesign.Space.panel)
                .padding(.bottom, PerchDesign.Space.section)

            Group {
                switch mode {
                case .attention: attentionContent
                case .allActivity: allActivityContent
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 360, height: panelHeight)
    }

    private var header: some View {
        HStack(spacing: PerchDesign.Space.row) {
            Image(systemName: "bird.fill")
                .font(PerchDesign.Symbol.headerBird)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Perch")
                .font(.title3.weight(.semibold))

            Spacer()

            Text(roster.waitingCount == 0 ? "All clear" : "\(roster.waitingCount) waiting")
                .font(.headline)
                .foregroundStyle(roster.waitingCount > 0 ? PerchDesign.ColorRole.attention : .secondary)
                .monospacedDigit()
                .accessibilityLabel(roster.waitingCount == 0 ? "Nothing waiting" : "\(roster.waitingCount) agents waiting")

            Button {
                Task { await roster.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh now")
            .accessibilityLabel("Refresh sessions")
        }
        .padding(PerchDesign.Space.panel)
    }

    private var panelHeight: CGFloat {
        mode == .attention && presentation.waitingCount == 0 ? 330 : 480
    }

    @ViewBuilder
    private var attentionContent: some View {
        if presentation.waitingSessions.isEmpty {
            calmZeroState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(presentation.waitingSessions) { item in
                        WaitingHandoffRowView(item: item) {
                            Task { try? await roster.focus(item.session) }
                        }
                        if item.id != presentation.waitingSessions.last?.id {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                .padding(.horizontal, PerchDesign.Space.panel)
                .padding(.bottom, PerchDesign.Space.section)
            }
        }
    }

    private var calmZeroState: some View {
        HStack(spacing: PerchDesign.Space.section) {
            Image(systemName: "bird")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing needs you")
                    .font(.body.weight(.medium))
                Text(presentation.observedCount == 0 ? "Perch is watching enabled providers." : "Working agents can stay in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, PerchDesign.Space.panel)
        .padding(.vertical, PerchDesign.Space.section)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var allActivityContent: some View {
        if presentation.allSessions.isEmpty {
            ContentUnavailableView("No agent sessions", systemImage: "bird")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(presentation.allSessions) { item in
                        SessionRowView(item: item) {
                            Task { try? await roster.focus(item.session) }
                        }
                        if item.id != presentation.allSessions.last?.id {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                .padding(.horizontal, PerchDesign.Space.panel)
                .padding(.bottom, PerchDesign.Space.section)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Local observation only")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, PerchDesign.Space.panel)
        .padding(.vertical, PerchDesign.Space.row)
    }
}
