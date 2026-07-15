import SwiftUI

enum PerchDesign {
    enum ColorRole {
        static let attention = Color.orange
        static let working = Color.blue
        static let resting = Color.secondary
        static let uncertain = Color.secondary
        static let separator = Color.primary.opacity(0.10)
        static let subtleSurface = Color.primary.opacity(0.035)
    }

    enum Space {
        static let compact: CGFloat = 6
        static let row: CGFloat = 10
        static let section: CGFloat = 12
        static let panel: CGFloat = 14
    }

    enum Shape {
        static let groupRadius: CGFloat = 12
        static let attentionRadius: CGFloat = 8
    }

    enum Symbol {
        static let perchBird = Font.system(size: 17, weight: .medium)
        static let headerBird = Font.system(size: 22, weight: .semibold)
    }
}

struct PerchOverviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
