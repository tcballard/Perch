import AppKit
import SwiftUI

struct PerchPanelView: View {
    let roster: RosterCoordinator
    @State private var mode: PanelMode = .attention

    private var presentation: AttentionPresentation {
        AttentionPresentation(sessions: roster.sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            AttentionOverviewView(presentation: presentation)
            modePicker
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

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
        .frame(width: 360, height: 480)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Perch")
                    .font(.headline)
                Text("\(roster.waitingCount) waiting")
                    .font(.caption)
                    .foregroundStyle(roster.waitingCount > 0 ? .orange : .secondary)
            }
            Spacer()
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
        .padding(12)
    }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(PanelMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Perch view")
    }

    @ViewBuilder
    private var attentionContent: some View {
        if presentation.waitingSessions.isEmpty {
            ContentUnavailableView(
                "Nothing needs you",
                systemImage: "checkmark.circle",
                description: Text(presentation.observedCount == 0 ? "Perch is watching enabled providers." : "Working agents can stay in the background.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(presentation.waitingSessions) { item in
                        WaitingHandoffRowView(item: item) {
                            Task { try? await roster.focus(item.session) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var allActivityContent: some View {
        if presentation.allSessions.isEmpty {
            ContentUnavailableView("No agent sessions", systemImage: "bird")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(presentation.allSessions) { item in
                        SessionRowView(item: item) {
                            Task { try? await roster.focus(item.session) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
        .padding(12)
    }
}
