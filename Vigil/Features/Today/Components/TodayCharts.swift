import Charts
import SwiftUI

/// One chart value in display units.
struct TodayChartPoint: Identifiable, Hashable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}

enum TodayChartScale {
    /// Maximum points drawn per series (the repository already buckets, this guards raw inputs).
    static let maxPoints = 300

    /// Y domain covering the values and the band with 12% padding; nil without data.
    static func domain(values: [Double], band: ClosedRange<Double>?) -> ClosedRange<Double>? {
        var all = values
        if let band { all += [band.lowerBound, band.upperBound] }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        let span = hi - lo
        let pad = span > 0 ? span * 0.12 : max(abs(hi) * 0.05, 1)
        return (lo - pad)...(hi + pad)
    }

    /// Four evenly spaced round-number gridlines that cover the values and the band, plus the matching y domain.
    static func niceAxis(values: [Double], band: ClosedRange<Double>?, count: Int = 4) -> (ticks: [Double], domain: ClosedRange<Double>)? {
        var all = values
        if let band { all += [band.lowerBound, band.upperBound] }
        guard let lo = all.min(), let hi = all.max(), count > 1 else { return nil }
        let intervals = Double(count - 1)
        let raw = max((hi - lo) / intervals, max(abs(hi), abs(lo)) * 0.02, 0.01)
        let magnitude = pow(10, floor(log10(raw)))
        for factor in [1.0, 2.0, 2.5, 5.0, 10.0, 20.0, 50.0] {
            let step = magnitude * factor
            guard step >= raw * 0.999 else { continue }
            let start = (lo / step).rounded(.down) * step
            if start + intervals * step >= hi - step * 1e-9 {
                let ticks = (0..<count).map { start + Double($0) * step }
                return (ticks, ticks[0]...ticks[count - 1])
            }
        }
        return nil
    }

    /// Evenly thins `points` to at most `limit`, always keeping the last one.
    static func downsample(_ points: [TodayChartPoint], limit: Int = maxPoints) -> [TodayChartPoint] {
        guard points.count > limit, limit > 1 else { return points }
        let stride = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * stride).rounded())] }
    }
}

/// Line + area chart with an optional baseline band, end marker and selection rule.
struct TodayLineChart: View {
    let points: [TodayChartPoint]
    var band: ClosedRange<Double>?
    var bandColor: Color = .vRecovery
    var color: Color = .vRecovery
    var yDomain: ClosedRange<Double>?
    var xDomain: ClosedRange<Date>?
    var xFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day()
    var height: CGFloat = 150
    var showsArea = true
    var showsYAxis = true
    /// Explicit solid gridlines (also the y labels when `showsYAxis`). Falls back to automatic marks.
    var yTicks: [Double]?
    @Binding var selection: Date?
    @Environment(\.vSurface) private var surface

    init(points: [TodayChartPoint], band: ClosedRange<Double>? = nil, bandColor: Color = .vRecovery, color: Color = .vRecovery,
         yDomain: ClosedRange<Double>? = nil, xDomain: ClosedRange<Date>? = nil,
         xFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day(), height: CGFloat = 150, showsArea: Bool = true,
         showsYAxis: Bool = true, yTicks: [Double]? = nil, selection: Binding<Date?> = .constant(nil)) {
        self.points = points
        self.band = band
        self.bandColor = bandColor
        self.color = color
        self.yDomain = yDomain
        self.xDomain = xDomain
        self.xFormat = xFormat
        self.height = height
        self.showsArea = showsArea
        self.showsYAxis = showsYAxis
        self.yTicks = yTicks
        _selection = selection
    }

    private var selected: TodayChartPoint? {
        guard let selection else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        let drawn = TodayChartScale.downsample(points)
        Chart {
            if let band { VBaselineBand(low: band.lowerBound, high: band.upperBound, color: bandColor) }
            ForEach(drawn) { point in
                if showsArea && drawn.count > 1 {
                    AreaMark(x: .value("Date", point.date), y: .value("Value", point.value)).vAreaStyle(color)
                }
                if drawn.count > 1 {
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value)).vLineStyle(color)
                }
            }
            if let last = drawn.last, selected == nil {
                VEndDot(x: .value("Date", last.date), y: .value("Value", last.value), color: color)
            }
            if let selected {
                RuleMark(x: .value("Date", selected.date)).foregroundStyle(Color.vChartBaseline)
                VPointMarker(x: .value("Date", selected.date), y: .value("Value", selected.value), color: color)
            }
        }
        .chartYAxis {
            if let yTicks {
                AxisMarks(values: yTicks) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(surface == .night ? Color.vNightFill : Color.vChartGrid)
                    if showsYAxis { AxisValueLabel().font(.vCaption2).foregroundStyle(surface.inkSecondary) }
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(surface == .night ? Color.vNightFill : Color.vChartGrid)
                    if showsYAxis { AxisValueLabel().font(.vCaption2).foregroundStyle(surface.inkSecondary) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: xFormat).font(.vCaption).foregroundStyle(surface.inkSecondary)
            }
        }
        .chartYScale(domain: yDomain ?? 0...1)
        .modifier(OptionalXDomain(domain: xDomain))
        .chartXSelection(value: $selection)
        .frame(height: height)
    }
}

private struct OptionalXDomain: ViewModifier {
    let domain: ClosedRange<Date>?
    func body(content: Content) -> some View {
        if let domain { content.chartXScale(domain: domain) } else { content }
    }
}

/// Small overline + big value + unit used above charts.
struct TodayBigValue: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String?
    var caption: String?
    /// Change against baseline, shown inline after the unit ("68 ms ↑ 12%").
    var delta: DeltaBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OverlineLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                Text(value).font(.vCustom(.heading, size: 40, weight: .bold, relativeTo: .largeTitle)).tracking(-0.02 * 40).foregroundStyle(.vInk)
                if let unit { Text(unit).font(.vCustom(.body, size: 17, weight: .semibold, relativeTo: .body)).foregroundStyle(.vInkSecondary) }
                if let delta { delta.padding(.leading, VSpacing.xs) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let caption { Text(caption).vTextStyle(.subheadline).foregroundStyle(.vInkSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Principal toolbar title used by the Today detail screens: name on top, date underneath.
struct TodayDetailTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.vCustom(.body, size: 17, weight: .bold, relativeTo: .headline)).foregroundStyle(.vInk)
            Text(subtitle).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
