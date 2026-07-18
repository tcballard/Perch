import SwiftUI
import WidgetKit

@main
struct PerchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: PerchWidgetSnapshotStorage.widgetKind,
            provider: PerchWidgetProvider()
        ) { entry in
            PerchWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor)
                }
        }
        .configurationDisplayName("Perch Attention")
        .description("See which local coding agent needs you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
