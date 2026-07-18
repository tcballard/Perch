import AppKit
import SwiftUI

struct PerchStatusLabel: View {
    let waitingCount: Int
    let dominantState: AgentState

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: statusImage)
                .renderingMode(.original)
            if waitingCount > 0 {
                Text(waitingCount, format: .number)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch dominantState {
        case .waiting: "Perch, \(waitingCount) sessions waiting"
        case .working: "Perch, agents working"
        case .idle, .done: "Perch, agents resting"
        case .unknown: "Perch, session state uncertain"
        }
    }

    private var statusImage: NSImage {
        let symbolName = dominantState == .unknown ? "bird" : "bird.fill"
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) ?? NSImage()
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [statusColor]))
        let image = base.withSymbolConfiguration(configuration) ?? base
        image.isTemplate = false
        return image
    }

    private var statusColor: NSColor {
        switch dominantState {
        case .waiting: .systemOrange
        case .working: .systemBlue
        case .idle, .done: .secondaryLabelColor
        case .unknown: .tertiaryLabelColor
        }
    }
}
