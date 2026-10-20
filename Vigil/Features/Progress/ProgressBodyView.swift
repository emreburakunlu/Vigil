import Charts
import SwiftUI

/// Progress · Body: body weight, resting HR, HRV, recovery vs. load.
struct ProgressBodyView: View {
    var key: ProgressLoadKey

    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = ProgressBodyModel()

    var body: some View {
        let formatter = settingsStore.formatter
        ProgressSegmentScaffold(phase: model.phase, retry: { Task { await reload() } }) {
            if let content = model.content {
                ForEach(ProgressBodyModel.metrics) { metric in
                    if let card = content.cards.first(where: { $0.metric == metric }) {
                        BodyMetricCardView(card: card, ticks: content.tickDates, today: container.repository.today, formatter: formatter)
                    } else {
                        ProgressCard(title: LocalizedStringKey(metric.displayName)) {
                            ProgressMessage(systemImage: "chart.line.downtrend.xyaxis", text: "Not available in this range.")
                        }
                    }
                }
                RecoveryLoadCard(days: content.recoveryLoad, ticks: content.recoveryLoadTicks)
            }
        }
        .task(id: key) { await reload() }
    }

    private func reload() async {
        await model.load(repository: container.repository, range: key.range)
    }
}

private struct BodyMetricCardView: View {
    let card: ProgressBodyCard
    let ticks: [Date]
    let today: LocalDay
    let formatter: VigilFormatter

    var body: some View {
        let color = Self.color(card.metric)
        let latest = formatter.format(card.metric, card.latest)
        let points = card.points.map { ProgressPoint(date: $0.date, value: toDisplay($0.value)) }
        let band = card.band.map { toDisplay($0.lowerBound)...toDisplay($0.upperBound) }
        let pill = Self.pillColors(card.changeIsGood)
        NavigationLink(value: AppRoute.metric(card.metric, today)) {
            VStack(alignment: .leading, spacing: VSpacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(card.metric.displayName)).vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel)
                        HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                            Text(latest.value).vTextStyle(.title).foregroundStyle(Color.vInk)
                            Text(latest.unit).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                        }
                    }
                    Spacer(minLength: VSpacing.s)
                    if let change = card.change {
                        Text(ProgressBodyModel.changeText(card.metric, change, formatter))
                            .font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
                            .foregroundStyle(pill.ink)
                            .padding(.horizontal, VSpacing.m).padding(.vertical, VSpacing.xxs + 1)
                            .background(pill.fill, in: .capsule)
                    }
                }
                Chart {
                    if let band {
                        RectangleMark(yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                            .foregroundStyle(color.opacity(0.14))
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(card.metric.shortName, point.value)).vLineStyle(color, width: 2.6)
                    }
                    if let last = points.last {
                        VEndDot(x: .value("Date", last.date), y: .value(card.metric.shortName, last.value), color: color)
                    }
                }
                .vChartAxes()
                .chartXAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 84)
                .accessibilityLabel("\(card.metric.displayName) trend")
                .accessibilityValue(progressSummary(points) { String(format: "%.1f", $0) })
                ProgressTicks(dates: ticks)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the metric detail")
    }

    private func toDisplay(_ value: Double) -> Double {
        card.metric == .bodyMass ? formatter.displayWeight(kilograms: value) : value
    }

    /// Delta pill colours, like the vitals: good = green, worse = amber, neutral = grey.
    static func pillColors(_ isGood: Bool?) -> (ink: Color, fill: Color) {
        switch isGood {
        case true: (.vPositive, .vPositiveTint)
        case false: (.vWarningInk, .vWarningTint)
        case nil: (.vInkLabel, .vFill)
        }
    }

    static func color(_ metric: HealthMetric) -> Color {
        switch metric {
        case .bodyMass: .vRun
        case .restingHeartRate: .vDanger
        default: .vPositive
        }
    }
}

private struct RecoveryLoadCard: View {
    let days: [ProgressRecoveryLoadDay]
    let ticks: [Date]

    var body: some View {
        ProgressCard(title: "Recovery vs. training load", trailing: String(localized: "Last \(days.count) days")) {
            if days.isEmpty {
                ProgressMessage(systemImage: "chart.bar", text: "Not available yet. Scores build up as you use Vigil.")
            } else {
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Load", day.load))
                            .foregroundStyle(Color.vStrain.opacity(0.35))
                            .cornerRadius(2)
                    }
                    ForEach(days.filter { $0.recovery != nil }) { day in
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Recovery", day.recovery ?? 0)).vLineStyle(.vRecovery, width: 2.6)
                    }
                    if let last = days.last(where: { $0.recovery != nil }), let value = last.recovery {
                        VEndDot(x: .value("Day", last.date), y: .value("Recovery", value), color: .vRecovery)
                    }
                }
                .vChartAxes()
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 160)
                .accessibilityLabel("Recovery percent and daily training load")
                .accessibilityValue(summary)
                ProgressTicks(dates: ticks)
                HStack(spacing: VSpacing.xxl) {
                    legend("Recovery %", .vRecovery)
                    legend("Daily training load", Color.vStrain.opacity(0.35))
                }
            }
        }
    }

    private var summary: String {
        let values = days.compactMap(\.recovery)
        guard !values.isEmpty else { return String(localized: "No data") }
        let average = Int((values.reduce(0, +) / Double(values.count)).rounded())
        return String(localized: "Average recovery \(average) percent over \(days.count) days")
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: VSpacing.xs) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Body") { ProgressBodyView(key: .preview).vigilPreview() }
#Preview("Body dark") { ProgressBodyView(key: .preview).vigilPreview().preferredColorScheme(.dark) }
