import AppKit
import SwiftUI

struct PerchPanelView: View {
    let roster: RosterCoordinator
    @Binding var desktopCompanionEnabled: Bool
    let setDesktopCompanionVisible: (Bool) -> Void
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
        .background(MenuBarPanelPlacementGuard())
        .onChange(of: desktopCompanionEnabled) { _, isEnabled in
            setDesktopCompanionVisible(isEnabled)
        }
    }

    private var header: some View {
        PerchSurfaceHeader(presentation: presentation) {
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
        mode == .attention && presentation.waitingCount == 0 ? 280 : 480
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
            Label("Local observation only", systemImage: "lock")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Desktop", isOn: $desktopCompanionEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Show Perch on the desktop")
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

/// `MenuBarExtra(.window)` can retain its old top edge when the SwiftUI content
/// changes height, placing the panel under the menu bar. Keep the native host
/// window, but clamp it to the screen's visible frame after every layout pass.
private struct MenuBarPanelPlacementGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, let screen = window.screen else { return }
            let visibleFrame = screen.visibleFrame
            var frame = window.frame
            let maximumY = visibleFrame.maxY - frame.height
            if frame.origin.y > maximumY {
                frame.origin.y = maximumY
                window.setFrameOrigin(frame.origin)
            }
        }
    }
}
