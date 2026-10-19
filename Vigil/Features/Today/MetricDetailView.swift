import Charts
import SwiftUI

/// State of the Metric detail screen.
@MainActor
@Observable
final class MetricDetailModel {
    enum Phase: Equatable { case loading, loaded, failed }

    private(set) var phase: Phase = .loading
    private(set) var series: MetricSeries?

    var metric: HealthMetric
    var range: MetricRange = .month
    let day: LocalDay

    init(metric: HealthMetric, day: LocalDay) {
        self.metric = metric
        self.day = day
    }

    var isStale: Bool { series.map { $0.metric != metric || $0.range != range } ?? true }

    struct Key: Hashable { var metric: HealthMetric; var range: MetricRange }
    var key: Key { Key(metric: metric, range: range) }

    func load(_ repository: VigilRepository) async {
        let (metric, range) = (metric, range)
        if series == nil { phase = .loading }
        do {
            let result = try await repository.metricSeries(metric, range: range, endingOn: day)
            guard !Task.isCancelled, metric == self.metric, range == self.range else { return }
            series = result
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, metric == self.metric, range == self.range else { return }
            phase = .failed
        }
    }
}

/// Shared metric detail for any `HealthMetric` with D / W / M / 6M / Y ranges.
struct MetricDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model: MetricDetailModel
    @State private var selection: Date?

    init(metric: HealthMetric, day: LocalDay) {
        _model = State(initialValue: MetricDetailModel(metric: metric, day: day))
    }

    private var formatter: VigilFormatter { settingsStore.formatter }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.cardGap) {
                if HealthMetric.vitals.contains(model.metric) { metricChips }
                switch model.phase {
                case .failed:
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load data",
                                   message: "Something went wrong reading your data.", actionTitle: "Try again") {
                        Task { await model.load(container.repository) }
                    }
                    .vCard()
                case .loading, .loaded:
                    if let series = model.series {
                        MetricDetailContent(series: series, metric: model.metric, range: $model.range, selection: $selection,
                                            formatter: formatter)
                            .redacted(reason: model.isStale ? .placeholder : [])
                            .allowsHitTesting(!model.isStale)
                    } else {
                        MetricDetailContent(series: MetricDetailModel.placeholder(model.metric, range: model.range, day: model.day),
                                            metric: model.metric, range: $model.range, selection: $selection, formatter: formatter)
                            .redacted(reason: .placeholder)
                            .allowsHitTesting(false)
                    }
                }
                Text(MetricPresentation.explanation(model.metric))
                    .vTextStyle(.subheadline).foregroundStyle(.vInkLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, VSpacing.s)
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .vScreenBackground()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TodayDetailTitle(title: model.metric.displayName, subtitle: MetricPresentation.subtitle(model.metric))
            }
        }
        .task(id: model.key) {
            selection = nil
            await model.load(container.repository)
        }
    }

    private var metricChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VSpacing.s) {
                ForEach(HealthMetric.vitals) { metric in
                    let isSelected = metric == model.metric
                    Button { model.metric = metric } label: {
                        Text(MetricPresentation.chipTitle(metric))
                            .font(.vCustom(.body, size: 14, weight: isSelected ? .bold : .semibold, relativeTo: .subheadline))
                            .foregroundStyle(isSelected ? Color.vInkOnInverse : Color.vInk)
                            .padding(.horizontal, VSpacing.xxl)
                            .frame(minHeight: 38)
                            .background(isSelected ? Color.vInverseFill : Color.vCard, in: .capsule)
                            .overlay(Capsule().strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.vPress)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }
}

extension MetricDetailModel {
    /// Empty series used for the redacted first frame.
    static func placeholder(_ metric: HealthMetric, range: MetricRange, day: LocalDay) -> MetricSeries {
        let interval = range.interval(endingOn: day)
        let step = interval.duration / 12
        let points = (0..<12).map { i in
            TimeSeriesPoint(interval: DateInterval(start: interval.start.addingTimeInterval(step * Double(i)), duration: step), value: 50 + Double(i % 4))
        }
        return MetricSeries(metric: metric, range: range, interval: interval, points: points, average: 52, minimum: 48, maximum: 58,
                            baseline: Baseline(mean: 52, standardDeviation: 4, sampleCount: 30), latest: nil, sourceName: nil)
    }
}

private struct MetricDetailContent: View {
    let series: MetricSeries
    let metric: HealthMetric
    @Binding var range: MetricRange
    @Binding var selection: Date?
    let formatter: VigilFormatter

    var body: some View {
        let display = MetricPresentation.display(series, formatter: formatter)
        VStack(spacing: VSpacing.cardGap) {
            VStack(alignment: .leading, spacing: VSpacing.xl) {
                VSegmentedControl(selection: $range, options: MetricRange.allCases) { LocalizedStringKey($0.rawValue) }
                if display.isEmpty {
                    EmptyStateView(systemImage: "chart.line.downtrend.xyaxis", title: "No data yet",
                                   message: "Nothing was recorded for \(metric.displayName.lowercased()) in this period.")
                } else {
                    chart(display)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard()
            if !display.isEmpty {
                HStack(spacing: VSpacing.m) {
                    summaryTile("Average", display.average)
                    summaryTile("Minimum", display.minimum)
                    summaryTile("Maximum", display.maximum)
                }
            }
            latestCard
        }
    }

    private func chart(_ display: MetricPresentation.Display) -> some View {
        let selected = selection.flatMap { date in
            display.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        let average = display.average
        return VStack(alignment: .leading, spacing: VSpacing.xl) {
            if let selected {
                TodayBigValue(label: LocalizedStringKey(selected.date.formatted(.dateTime.month(.abbreviated).day().hour())),
                              value: formatter.number(selected.value, fractionDigits: MetricPresentation.fractionDigits(metric)),
                              unit: display.unit,
                              caption: MetricPresentation.rangeLabel(series.interval, range: range))
            } else {
                TodayBigValue(label: "Average", value: average?.value ?? "–", unit: average?.unit,
                              caption: MetricPresentation.rangeLabel(series.interval, range: range))
            }
            TodayLineChart(points: display.points, band: display.band, bandColor: .vRecovery, color: .vRecovery, yDomain: display.yDomain,
                           xDomain: series.interval.start...series.interval.end, xFormat: MetricPresentation.xFormat(range), height: 190,
                           showsArea: false, selection: $selection)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(metric.displayName), \(MetricPresentation.rangeLabel(series.interval, range: range))"))
                .accessibilityValue(Text("Average \(average?.value ?? "none") \(average?.unit ?? ""), minimum \(display.minimum?.value ?? "none"), maximum \(display.maximum?.value ?? "none"), \(display.points.count) points"))
            if let text = display.baselineText {
                HStack(spacing: VSpacing.s) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.vRecovery.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.vChartBaseline, lineWidth: 1))
                        .frame(width: 14, height: 14)
                    Text(text).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkLabel)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func summaryTile(_ title: LocalizedStringKey, _ stat: MetricPresentation.Stat?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(stat?.value ?? "–").font(.vCustom(.heading, size: 24, weight: .bold, relativeTo: .title2)).foregroundStyle(.vInk)
                if let unit = stat?.unit, !unit.isEmpty { Text(unit).vTextStyle(.caption).foregroundStyle(.vInkSecondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(VSpacing.cardPaddingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
        .accessibilityElement(children: .combine)
    }

    private var latestCard: some View {
        let ref = MetricPresentation.reference(series)
        let reading = MetricPresentation.latestReading(series)
        let delta = reading.flatMap { TodayPresentation.deltaDisplay($0, formatter: formatter) }
        return MetricRowList {
            if let latest = series.latest {
                let stat = MetricPresentation.stat(latest.value, metric: metric, reference: ref, formatter: formatter)
                MetricRow(title: LocalizedStringKey(MetricPresentation.latestTitle(metric)), value: stat.value, unit: stat.unit,
                          delta: delta.map { DeltaBadge($0.text, direction: $0.direction, tone: $0.tone) })
            }
            if let baseline = series.baseline, baseline.isEstablished {
                let stat = metric == .wristTemperature
                    ? MetricPresentation.Stat(value: String(localized: "0"), unit: formatter.temperatureDelta(celsius: 0).unit)
                    : MetricPresentation.stat(baseline.mean, metric: metric, reference: ref, formatter: formatter)
                MetricRow(title: "30-day baseline", value: stat.value, unit: stat.unit)
            }
            MetricRow(title: "Source", value: series.sourceName ?? String(localized: "Not available"))
        }
        .padding(.horizontal, VSpacing.cardPadding)
        .padding(.vertical, VSpacing.xxs)
        .frame(maxWidth: .infinity)
        .vCard(padding: 0)
    }
}

#Preview { MetricDetailView(metric: .heartRateVariability, day: .today()).vigilPreview() }
#Preview("Wrist temperature") { MetricDetailView(metric: .wristTemperature, day: .today()).vigilPreview() }
#Preview("Body weight dark") { MetricDetailView(metric: .bodyMass, day: .today()).vigilPreview().preferredColorScheme(.dark) }
#Preview("Partial data") { MetricDetailView(metric: .wristTemperature, day: .today()).vigilPreview(.partialData) }
