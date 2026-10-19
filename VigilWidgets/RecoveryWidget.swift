import SwiftUI
import WidgetKit

/// Small · Recovery ("78% · Push day").
struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.recovery, provider: SnapshotTimelineProvider()) { entry in
            RecoveryWidgetView(entry: entry)
                .containerBackground(Color.vCard, for: .widget)
                .widgetURL(DeepLink.recovery(nil).url)
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery and readiness.")
        .supportedFamilies([.systemSmall])
    }
}

struct RecoveryWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xxs) {
            Text("Recovery").vTextStyle(.footnote).foregroundStyle(.vInkSecondary)
            Text(entry.snapshot?.recoveryPercent.map { "\($0)%" } ?? "–")
                .vTextStyle(.title)
                .foregroundStyle(.vInk)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .systemSmall) {
    RecoveryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder())
}
