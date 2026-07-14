import SwiftUI

struct PerchStatusLabel: View {
    let waitingCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: waitingCount > 0 ? "bird.fill" : "bird")
            if waitingCount > 0 {
                Text(waitingCount, format: .number)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        waitingCount == 0
            ? "Perch, no sessions waiting"
            : "Perch, \(waitingCount) sessions waiting"
    }
}
