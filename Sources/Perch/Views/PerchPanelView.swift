import AppKit
import SwiftUI

struct PerchPanelView: View {
    let roster: RosterCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if roster.sessions.isEmpty {
                ContentUnavailableView(
                    "No agent sessions",
                    systemImage: "bird",
                    description: Text("Perch is watching enabled providers.")
                )
                .frame(minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(roster.sessions) { session in
                            SessionRowView(session: session) {
                                Task { try? await roster.focus(session) }
                            }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            footer
        }
        .frame(width: 360, height: 420)
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
            .help("Refresh now")
            .accessibilityLabel("Refresh sessions")
        }
        .padding(12)
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
