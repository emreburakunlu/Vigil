import SwiftUI
import WidgetKit

/// Medium · Daily scores (Recovery, Sleep, Strain).
struct DailyScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.dailyScores, provider: SnapshotTimelineProvider()) { entry in
            DailyScoresWidgetView(entry: entry)
                .containerBackground(Color.vCard, for: .widget)
                .widgetURL(DeepLink.today.url)
        }
        .configurationDisplayName("Daily scores")
        .description("Recovery, Sleep and Strain at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

struct DailyScoresWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        HStack {
            score("Recovery", entry.snapshot?.recoveryPercent)
            score("Sleep", entry.snapshot?.sleepScore)
            score("Strain", entry.snapshot?.strain)
        }
    }

    private func score(_ title: String, _ value: Int?) -> some View {
        VStack(spacing: VSpacing.xxs) {
            Text(value.map(String.init) ?? "–").vTextStyle(.title).foregroundStyle(.vInk)
            Text(title).vTextStyle(.caption).foregroundStyle(.vInkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .systemMedium) {
    DailyScoresWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder())
}
