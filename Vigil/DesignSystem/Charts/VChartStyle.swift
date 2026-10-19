import Charts
import SwiftUI

// MARK: - Swift Charts style helpers
//
// Owner: design-system agent. Gridlines `vChartGrid`, dashed baselines `vChartBaseline`, axis labels
// 11–12 pt `vInkSecondary`. Charts should always expose an `accessibilityLabel`/`accessibilityValue` summary.

extension View {
    /// Standard Vigil axes: faint horizontal grid, no vertical grid, small secondary-ink labels, no axis line.
    ///
    /// ```swift
    /// Chart { … }.vChartAxes()
    /// Chart { … }.vChartAxes(xValues: .stride(by: .day), xFormat: .dateTime.weekday(.narrow))
    /// ```
    func vChartAxes(
        yCount: Int = 3,
        showsYAxis: Bool = false,
        xValues: AxisMarkValues = .automatic,
        xFormat: Date.FormatStyle = .dateTime.weekday(.narrow)
    ) -> some View {
        modifier(VChartAxesModifier(yCount: yCount, showsYAxis: showsYAxis, xValues: xValues, xFormat: xFormat))
    }
}

private struct VChartAxesModifier: ViewModifier {
    let yCount: Int
    let showsYAxis: Bool
    let xValues: AxisMarkValues
    let xFormat: Date.FormatStyle
    @Environment(\.vSurface) private var surface

    func body(content: Content) -> some View {
        content
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: yCount)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(surface == .night ? Color.vNightFill : Color.vChartGrid)
                    if showsYAxis {
                        AxisValueLabel().font(.vCaption2).foregroundStyle(surface.inkSecondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xValues) { _ in
                    AxisValueLabel(format: xFormat).font(.vCaption).foregroundStyle(surface.inkSecondary)
                }
            }
    }
}

extension ChartContent {
    /// Standard line series: 2.5 pt round-joined line in `color`, monotone interpolation.
    func vLineStyle(_ color: Color, width: CGFloat = 2.5) -> some ChartContent {
        self
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .foregroundStyle(color)
    }

    /// Standard area under a line: vertical gradient from 22% to 0% of `color`.
    func vAreaStyle(_ color: Color) -> some ChartContent {
        self
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
    }

    /// Standard bar: 6 pt radius, `color` (or the soft variant for non-highlighted bars).
    func vBarStyle(_ color: Color, cornerRadius: CGFloat = 6) -> some ChartContent {
        self
            .cornerRadius(cornerRadius)
            .foregroundStyle(color)
    }
}

/// Baseline band (e.g. the 30-day normal range for HRV): a faint horizontal band with dashed edges.
///
/// ```swift
/// Chart { VBaselineBand(low: 55, high: 70) ; LineMark(…) }
/// ```
struct VBaselineBand: ChartContent {
    let low: Double
    let high: Double
    var color: Color = .vRecovery

    var body: some ChartContent {
        RectangleMark(yStart: .value("Baseline low", low), yEnd: .value("Baseline high", high))
            .foregroundStyle(color.opacity(0.12))
        RuleMark(y: .value("Baseline low", low))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(Color.vChartBaseline)
        RuleMark(y: .value("Baseline high", high))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(Color.vChartBaseline)
    }
}

/// Dashed reference line (goal, average).
struct VReferenceLine: ChartContent {
    let value: Double
    var label: LocalizedStringKey?
    var color: Color = .vChartBaseline

    var body: some ChartContent {
        RuleMark(y: .value("Reference", value))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(color)
    }
}

/// Selection dot (white-ringed) drawn at the selected point.
struct VPointMarker: ChartContent {
    let x: PlottableValue<Date>
    let y: PlottableValue<Double>
    var color: Color = .vAccent

    var body: some ChartContent {
        PointMark(x: x, y: y)
            .symbol {
                Circle().fill(color).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.vCard, lineWidth: 2))
            }
    }
}

private struct ChartPreview: View {
    struct P: Identifiable { let id = UUID(); let d: Date; let v: Double }
    let data = (0..<14).map { P(d: Calendar.current.date(byAdding: .day, value: -13 + $0, to: .now) ?? .now, v: 60 + Double(($0 * 37) % 17)) }
    var body: some View {
        Chart {
            VBaselineBand(low: 62, high: 72)
            ForEach(data) { p in
                AreaMark(x: .value("Day", p.d), y: .value("HRV", p.v)).vAreaStyle(.vRecovery)
                LineMark(x: .value("Day", p.d), y: .value("HRV", p.v)).vLineStyle(.vRecovery)
            }
        }
        .vChartAxes(xValues: .stride(by: .day, count: 2))
        .chartYScale(domain: 50...85)
        .frame(height: 160)
        .vCard()
        .padding()
        .background(Color.vBackground)
        .accessibilityLabel("HRV over 14 days")
    }
}

#Preview("Chart") { ChartPreview() }
