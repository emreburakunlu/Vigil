import SwiftUI
import WidgetKit

/// Medium · Weekly progress (running distance, lifting sessions).
struct WeeklyProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.weeklyProgress, provider: SnapshotTimelineProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
                .containerBackground(Color.vCard, for: .widget)
                .widgetURL(DeepLink.train.url)
        }
        .configurationDisplayName("Weekly progress")
        .description("Running distance and lifting sessions over the last 7 days.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeeklyProgressWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        let snapshot = entry.snapshot ?? .placeholder()
        let formatter = VigilFormatter(units: snapshot.units)
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Text("Last 7 days").vTextStyle(.footnote).foregroundStyle(.vInkSecondary)
            Text("Running \(formatter.distance(meters: snapshot.weeklyRunDistanceMeters, fractionDigits: 1).value) / \(formatter.distance(meters: snapshot.weeklyRunGoalMeters, fractionDigits: 0).text)")
                .vTextStyle(.bodyStrong).foregroundStyle(.vInk)
            Text("Lifting \(snapshot.weeklyLiftSessions) / \(snapshot.weeklyLiftGoal) sessions")
                .vTextStyle(.bodyStrong).foregroundStyle(.vInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemMedium) {
    WeeklyProgressWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder())
}
