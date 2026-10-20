import SwiftUI
import WidgetKit

/// Small · Recovery ring with band and readiness label. Also Lock Screen circular.
struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.WidgetKind.recovery, provider: SnapshotTimelineProvider()) { entry in
            RecoveryWidgetView(entry: entry)
                .vigilWidgetContainer()
                .widgetURL(entry.snapshot == nil ? DeepLink.today.url : DeepLink.recovery(nil).url)
        }
        .configurationDisplayName("Recovery")
        .description("Today's recovery and readiness.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryCircular: circular(snapshot)
            default: small(snapshot)
            }
        } else {
            WidgetNeedsUpdateView()
        }
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        let band = snapshot.resolvedRecoveryBand ?? .green
        let percent = snapshot.recoveryPercent
        return VStack(spacing: VSpacing.xs) {
            HStack {
                Text("Recovery").vTextStyle(.footnote).fontWeight(.bold).foregroundStyle(Color.vInk)
                Spacer(minLength: 0)
                VigilMark(size: 16)
            }
            Spacer(minLength: 0)
            WidgetRing(progress: Double(percent ?? 0) / 100, color: band.ringColor, track: band.trackColor, diameter: 86) {
                Text(percent.map { "\($0)%" } ?? "–")
                    .vTextStyle(.title2)
                    .foregroundStyle(Color.vInk)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(snapshot.readinessLabel ?? bandName(band))
                .vTextStyle(.caption).fontWeight(.bold)
                .foregroundStyle(band.inkColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(snapshot))
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        Gauge(value: Double(snapshot.recoveryPercent ?? 0), in: 0...100) {
            Text("Recovery")
        } currentValueLabel: {
            Text(snapshot.recoveryPercent.map(String.init) ?? "–")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(accessibilityText(snapshot))
    }

    private func bandName(_ band: RecoveryBand) -> String {
        switch band {
        case .green: "Green"
        case .yellow: "Yellow"
        case .red: "Red"
        }
    }

    private func accessibilityText(_ snapshot: WidgetSnapshot) -> String {
        guard let percent = snapshot.recoveryPercent else { return "Recovery not available" }
        return "Recovery \(percent) percent" + (snapshot.readinessLabel.map { ", \($0)" } ?? "")
    }
}

#Preview("Small", as: .systemSmall) {
    RecoveryWidget()
} timeline: {
    WidgetPreviewData.fresh
    WidgetPreviewData.stale
}

#Preview("Lock Screen", as: .accessoryCircular) {
    RecoveryWidget()
} timeline: {
    WidgetPreviewData.fresh
}
