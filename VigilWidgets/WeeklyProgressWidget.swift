import SwiftUI
import WidgetKit

/// Medium · Weekly progress (running distance vs. goal, lifting sessions vs. goal).
struct WeeklyProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.weeklyProgress, provider: SnapshotTimelineProvider()) { entry in
            WeeklyProgressWidgetView(entry: entry)
                .vigilWidgetContainer()
                .widgetURL(entry.snapshot == nil ? DeepLink.today.url : DeepLink.train.url)
        }
        .configurationDisplayName("Weekly progress")
        .description("Running distance and lifting sessions over the last 7 days.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeeklyProgressWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            WidgetNeedsUpdateView()
        }
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let formatter = VigilFormatter(units: snapshot.units)
        let run = formatter.distance(meters: snapshot.weeklyRunDistanceMeters, fractionDigits: 1)
        let goal = formatter.distance(meters: snapshot.weeklyRunGoalMeters, fractionDigits: 0)
        return VStack(spacing: VSpacing.l) {
            WidgetHeader(title: "Last 7 days", trailing: dateRange(snapshot))
            row(icon: "figure.run", title: "Running", value: run.value, suffix: "/ \(goal.text)",
                tint: .vRun) {
                bar(progress: snapshot.runProgress, color: .vRun)
            }
            row(icon: "dumbbell.fill", title: "Lifting", value: "\(snapshot.weeklyLiftSessions)",
                suffix: "/ \(snapshot.weeklyLiftGoal) sessions", tint: .vLift) {
                segments(done: snapshot.weeklyLiftSessions, goal: snapshot.weeklyLiftGoal, color: .vLift)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 7 days. Running \(run.text) of \(goal.text). Lifting \(snapshot.weeklyLiftSessions) of \(snapshot.weeklyLiftGoal) sessions.")
    }

    private func row<Bar: View>(icon: String, title: String, value: String, suffix: String,
                                tint: Color, @ViewBuilder bar: () -> Bar) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon)
                    .vTextStyle(.subheadline).fontWeight(.bold)
                    .foregroundStyle(Color.vInk)
                    .labelStyle(TintedIconLabelStyle(tint: tint))
                Spacer(minLength: VSpacing.s)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).vTextStyle(.bodyStrong).fontWeight(.heavy).foregroundStyle(Color.vInk)
                    Text(suffix).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
                }
                .lineLimit(1)
            }
            bar()
        }
    }

    private var trackColor: Color { renderingMode == .fullColor ? .vFill : .primary.opacity(0.2) }
    private func fillColor(_ color: Color) -> Color { renderingMode == .fullColor ? color : .primary }

    private func bar(progress: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule().fill(fillColor(color)).frame(width: max(progress > 0 ? 9 : 0, proxy.size.width * progress))
                    .widgetAccentable()
            }
        }
        .frame(height: 9)
    }

    private func segments(done: Int, goal: Int, color: Color) -> some View {
        let count = max(goal, 1)
        return HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule().fill(index < done ? fillColor(color) : trackColor)
                    .widgetAccentable(index < done)
            }
        }
        .frame(height: 9)
    }

    private func dateRange(_ snapshot: WidgetSnapshot) -> String {
        let calendar = Calendar.current
        let sameMonth = calendar.isDate(snapshot.weekStart, equalTo: snapshot.weekEnd, toGranularity: .month)
        let start = snapshot.weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = sameMonth ? snapshot.weekEnd.formatted(.dateTime.day()) : snapshot.weekEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }
}

/// Small coloured SF Symbol before the title.
private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint).imageScale(.small)
            configuration.title
        }
    }
}

#Preview("Weekly", as: .systemMedium) {
    WeeklyProgressWidget()
} timeline: {
    WidgetPreviewData.fresh
    WidgetPreviewData.imperial
    WidgetPreviewData.stale
}
