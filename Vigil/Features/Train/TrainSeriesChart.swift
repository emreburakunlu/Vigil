import Charts
import SwiftUI

/// Line + area chart over a downsampled run series. `invertY` plots faster (lower) pace higher.
/// Axes are hidden except an optional shared x axis (distance ticks or elapsed minutes).
struct TrainSeriesChart: View {
    let points: [TrainChartPoint]
    let color: Color
    var invertY = false
    var xMax: Double
    var height: CGFloat = 84
    /// Tick positions (x units) and their labels; nil hides the x axis.
    var xTicks: [(value: Double, label: String)]?

    private var plotted: [TrainChartPoint] {
        invertY ? points.map { TrainChartPoint(id: $0.id, x: $0.x, y: -$0.y) } : points
    }

    var body: some View {
        let data = plotted
        let lo = data.map(\.y).min() ?? 0
        let hi = data.map(\.y).max() ?? 1
        let pad = max((hi - lo) * 0.12, 1)
        Chart {
            ForEach(data) { point in
                AreaMark(x: .value("Position", point.x), yStart: .value("Floor", lo - pad), yEnd: .value("Value", point.y))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Position", point.x), y: .value("Value", point.y))
                    .vLineStyle(color, width: 2.2)
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXScale(domain: 0...max(xMax, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            if let xTicks {
                AxisMarks(values: xTicks.map(\.value)) { value in
                    AxisValueLabel {
                        if let raw = value.as(Double.self), let tick = xTicks.first(where: { $0.value == raw }) {
                            Text(tick.label).font(.vCaption).foregroundStyle(Color.vInkSecondary)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}
