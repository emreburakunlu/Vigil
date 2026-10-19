import SwiftUI
import WidgetKit

/// Medium · Daily scores (Recovery, Sleep, Strain). Also Lock Screen rectangular.
struct DailyScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.dailyScores, provider: SnapshotTimelineProvider()) { entry in
            DailyScoresWidgetView(entry: entry)
                .vigilWidgetContainer()
                .widgetURL(DeepLink.today.url)
        }
        .configurationDisplayName("Daily scores")
        .description("Recovery, Sleep and Strain at a glance.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct DailyScoresWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            if family == .accessoryRectangular {
                rectangular(snapshot)
            } else {
                medium(snapshot)
            }
        } else {
            WidgetNeedsUpdateView()
        }
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        let formatter = VigilFormatter(units: snapshot.units)
        let band = snapshot.resolvedRecoveryBand ?? .green
        return VStack(spacing: VSpacing.s) {
            WidgetHeader(title: "Today", trailing: "Updated \(formatter.timeOfDay(snapshot.generatedAt))")
            HStack(spacing: VSpacing.xs) {
                Link(destination: DeepLink.recovery(nil).url) {
                    column("Recovery", value: snapshot.recoveryPercent, color: band.ringColor, track: band.trackColor)
                }
                column("Sleep", value: snapshot.sleepScore, color: VScoreKind.sleep.color, track: VScoreKind.sleep.track)
                column("Strain", value: snapshot.strain, color: VScoreKind.strain.color, track: VScoreKind.strain.track)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func column(_ title: String, value: Int?, color: Color, track: Color) -> some View {
        VStack(spacing: VSpacing.xs) {
            WidgetRing(progress: Double(value ?? 0) / 100, color: color, track: track, diameter: 72) {
                Text(value.map(String.init) ?? "–").vTextStyle(.title2).foregroundStyle(Color.vInk)
            }
            Text(title).vTextStyle(.caption).fontWeight(.bold).foregroundStyle(Color.vInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(title) \($0)" } ?? "\(title) not available")
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Vigil").font(.headline).widgetAccentable()
            Text("Recovery \(snapshot.recoveryPercent.map { "\($0)%" } ?? "–")")
            Text("Sleep \(snapshot.sleepScore.map(String.init) ?? "–") · Strain \(snapshot.strain.map(String.init) ?? "–")")
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Medium", as: .systemMedium) {
    DailyScoresWidget()
} timeline: {
    WidgetPreviewData.fresh
    WidgetPreviewData.stale
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    DailyScoresWidget()
} timeline: {
    WidgetPreviewData.fresh
}
