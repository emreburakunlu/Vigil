import Charts
import SwiftUI

/// Progress · Body: body weight, resting HR, HRV, recovery vs. load.
struct ProgressBodyView: View {
    var range: ProgressRange = .threeMonths

    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = ProgressBodyModel()

    var body: some View {
        let key = ProgressLoadKey(range: range, units: settingsStore.settings.units)
        ProgressSegmentScaffold(phase: model.phase, retry: { Task { await reload(key) } }) {
            if let content = model.content {
                ForEach(ProgressBodyModel.metrics) { metric in
                    if let card = content.cards.first(where: { $0.metric == metric }) {
                        BodyMetricCardView(card: card, ticks: content.tickDates, today: container.repository.today)
                    } else {
                        ProgressCard(title: LocalizedStringKey(metric.displayName)) {
                            ProgressMessage(systemImage: "chart.line.downtrend.xyaxis", text: "Not available in this range.")
                        }
                    }
                }
                RecoveryLoadCard(days: content.recoveryLoad, ticks: content.recoveryLoadTicks)
            }
        }
        .task(id: key) { await reload(key) }
    }

    private func reload(_ key: ProgressLoadKey) async {
        await model.load(repository: container.repository, range: key.range, formatter: settingsStore.formatter)
    }
}

private struct BodyMetricCardView: View {
    let card: ProgressBodyCard
    let ticks: [Date]
    let today: LocalDay

    var body: some View {
        let color = Self.color(card.metric)
        NavigationLink(value: AppRoute.metric(card.metric, today)) {
            VStack(alignment: .leading, spacing: VSpacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(card.metric.displayName)).vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel)
                        HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                            Text(card.latest.value).vTextStyle(.title).foregroundStyle(Color.vInk)
                            Text(card.latest.unit).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                        }
                    }
                    Spacer(minLength: VSpacing.s)
                    if let change = card.changeText {
                        Text(change).font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
                            .foregroundStyle(card.changeIsGood == true ? Color.vPositive : Color.vInkLabel)
                            .padding(.horizontal, VSpacing.m).padding(.vertical, VSpacing.xxs + 1)
                            .background(card.changeIsGood == true ? Color.vPositiveTint : Color.vFill, in: .capsule)
                    }
                }
                Chart {
                    if let band = card.band {
                        RectangleMark(yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                            .foregroundStyle(color.opacity(0.14))
                    }
                    ForEach(card.points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(card.metric.shortName, point.value)).vLineStyle(color, width: 2.6)
                    }
                    if let last = card.points.last {
                        VPointMarker(x: .value("Date", last.date), y: .value(card.metric.shortName, last.value), color: color)
                    }
                }
                .vChartAxes()
                .chartXAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 84)
                .accessibilityLabel("\(card.metric.displayName) trend")
                .accessibilityValue(progressSummary(card.points) { String(format: "%.1f", $0) })
                ProgressTicks(dates: ticks)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the metric detail")
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

#Preview("Body") { ProgressBodyView().vigilPreview() }
#Preview("Body dark") { ProgressBodyView().vigilPreview().preferredColorScheme(.dark) }
