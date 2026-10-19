import Charts
import SwiftUI

/// Progress · Lifting: sessions, time, calories, intensity, consistency.
struct ProgressLiftingView: View {
    var range: ProgressRange = .threeMonths

    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = ProgressLiftingModel()

    var body: some View {
        let formatter = settingsStore.formatter
        let key = ProgressLoadKey(range: range, units: settingsStore.settings.units)
        ProgressSegmentScaffold(phase: model.phase, retry: { Task { await reload(key) } }) {
            if let content = model.content {
                if content.totalSessions == 0 {
                    EmptyStateView(systemImage: "dumbbell", title: "No lifting yet",
                                   message: "Strength workouts saved to Apple Health show up here.")
                        .vCard()
                } else {
                    SessionsCard(content: content)
                    TimeCaloriesCard(content: content, formatter: formatter)
                    IntensityCard(content: content, formatter: formatter)
                }
                ConsistencyCard(heatmap: content.heatmap)
            }
        }
        .task(id: key) { await reload(key) }
    }

    private func reload(_ key: ProgressLoadKey) async {
        await model.load(repository: container.repository, range: key.range)
    }
}

private struct SessionsCard: View {
    let content: ProgressLiftingContent

    var body: some View {
        let average = content.averageSessions.formatted(.number.precision(.fractionLength(1)))
        ProgressCard(title: "Sessions per week", trailing: String(localized: "avg \(average)")) {
            Chart {
                ForEach(content.sessions) { bar in
                    BarMark(x: .value("Week", String(bar.id)), y: .value("Sessions", bar.value))
                        .vBarStyle(bar.id == content.sessions.last?.id ? .vLift : (bar.value >= Double(content.sessionGoal) ? .vLift.opacity(0.75) : .vLiftSoft),
                                   cornerRadius: 5)
                }
                RuleMark(y: .value("Goal", Double(content.sessionGoal)))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Color.vInk)
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Goal \(content.sessionGoal)").vTextStyle(.caption2).foregroundStyle(Color.vInk)
                    }
            }
            .vChartAxes()
            .chartXAxis(.hidden)
            .chartYScale(domain: 0...max(Double(content.sessionGoal), content.sessions.map(\.value).max() ?? 0) + 1)
            .frame(height: 130)
            .accessibilityLabel("Lifting sessions per week")
            .accessibilityValue(progressSummary(content.sessions.map { ProgressPoint(date: $0.start, value: $0.value) }) { String(Int($0)) })
            ProgressTicks(dates: content.tickDates)
        }
    }
}

private struct TimeCaloriesCard: View {
    let content: ProgressLiftingContent
    let formatter: VigilFormatter

    var body: some View {
        ProgressCard(title: "Time & calories") {
            mini(title: "Lifting time", value: formatter.duration(content.averageTime), unit: String(localized: "avg / week"),
                 bars: content.time, color: .vLiftSoft)
            mini(title: "Active calories", value: formatter.number(content.averageCalories, fractionDigits: 0), unit: String(localized: "kcal avg / week"),
                 bars: content.calories, color: .vLift)
        }
    }

    private func mini(title: LocalizedStringKey, value: String, unit: String, bars: [ProgressBar], color: Color) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).vTextStyle(.bodyStrong).foregroundStyle(Color.vInkLabel)
                Spacer()
                Text(value).vTextStyle(.statValueSmall).foregroundStyle(Color.vInk)
                Text(unit).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
            }
            Chart(bars) { bar in
                BarMark(x: .value("Week", String(bar.id)), y: .value("Value", bar.value))
                    .vBarStyle(bar.id == bars.last?.id ? Color.vLift : color, cornerRadius: 3)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 64)
            .accessibilityLabel(Text(title))
            .accessibilityValue("\(value) \(unit)")
        }
    }
}

private struct IntensityCard: View {
    let content: ProgressLiftingContent
    let formatter: VigilFormatter

    var body: some View {
        ProgressCard(title: "Intensity") {
            HStack(alignment: .top, spacing: VSpacing.l) {
                if let hr = content.heartRate {
                    tile(title: "Avg session HR", value: formatter.number(hr.latest, fractionDigits: 0), unit: "bpm",
                         delta: nil, series: hr, color: .vDanger)
                }
                if let strain = content.strain {
                    tile(title: "Avg session strain", value: formatter.number(strain.latest, fractionDigits: 0), unit: nil,
                         delta: strain.delta, series: strain, color: .vStrain)
                }
            }
            if content.heartRate == nil && content.strain == nil {
                ProgressMessage(systemImage: "heart.slash", text: "Not available. Heart rate wasn't recorded for these sessions.")
            }
        }
    }

    private func tile(title: LocalizedStringKey, value: String, unit: String?, delta: Double?, series: ProgressIntensitySeries, color: Color) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.xs) {
            Text(title).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: VSpacing.xxs) {
                Text(value).vTextStyle(.title).foregroundStyle(Color.vInk)
                if let unit { Text(unit).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary) }
                if let delta, abs(delta) >= 0.5 {
                    Text("\(delta > 0 ? "↑" : "↓") \(formatter.number(abs(delta), fractionDigits: 0))")
                        .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Chart(series.points) { point in
                LineMark(x: .value("Week", point.date), y: .value("Value", point.value)).vLineStyle(color)
                PointMark(x: .value("Week", point.date), y: .value("Value", point.value))
                    .symbolSize(series.points.count == 1 ? 60 : 0).foregroundStyle(color)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 56)
            .accessibilityLabel(Text(title))
            .accessibilityValue(progressSummary(series.points) { formatter.number($0, fractionDigits: 0) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VSpacing.cardPaddingCompact)
        .background(Color.vFill.opacity(0.6), in: .rect(cornerRadius: VRadius.chip, style: .continuous))
    }
}

private struct ConsistencyCard: View {
    let heatmap: ProgressHeatmap
    @Environment(\.calendar) private var calendar
    @State private var width: CGFloat = 300

    private let gap: CGFloat = 2
    private let labelWidth: CGFloat = 16

    var body: some View {
        ProgressCard(title: "Consistency", trailing: String(localized: "\(heatmap.trainingDays) training days")) {
            Color.clear.frame(height: 0)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            let columns = heatmap.columns.count
            let size = max(4, (width - labelWidth - 4 - gap * CGFloat(columns - 1)) / CGFloat(max(columns, 1)))
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(rowLabel(row)).font(.vCustom(.body, size: 10, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(Color.vInkSecondary)
                            .frame(width: labelWidth, height: size)
                            .minimumScaleFactor(0.5)
                    }
                }
                HStack(spacing: gap) {
                    ForEach(heatmap.columns.indices, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(heatmap.columns[column]) { cell in
                                RoundedRectangle(cornerRadius: min(3, size / 3), style: .continuous)
                                    .fill(color(cell.kind)).frame(width: size, height: size)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Consistency heatmap")
            .accessibilityValue("\(heatmap.trainingDays) training days")
            HStack(spacing: VSpacing.xxl) {
                legend("Run", .vRunSoft)
                legend("Lift", .vLift)
                legend("Both", .vInk)
                legend("Rest", .vFill)
            }
        }
    }

    private func rowLabel(_ row: Int) -> String {
        guard row % 2 == 0 else { return "" }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(calendar.firstWeekday - 1 + row) % 7]
    }

    private func color(_ kind: ProgressDayKind) -> Color {
        switch kind {
        case .rest: .vFill
        case .run: .vRunSoft
        case .lift: .vLift
        case .both: .vInk
        case .future: .clear
        }
    }

    private func legend(_ title: LocalizedStringKey, _ color: Color) -> some View {
        HStack(spacing: VSpacing.xs) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 12, height: 12)
            Text(title).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Lifting") { ProgressLiftingView().vigilPreview() }
#Preview("Lifting dark") { ProgressLiftingView().vigilPreview().preferredColorScheme(.dark) }
