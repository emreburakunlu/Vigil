import Charts
import SwiftUI

/// Progress · Running: distance, pace at similar heart rate, VO₂ max, personal bests, training load.
struct ProgressRunningView: View {
    var key: ProgressLoadKey

    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = ProgressRunningModel()

    var body: some View {
        let formatter = settingsStore.formatter
        ProgressSegmentScaffold(phase: model.phase, retry: { Task { await reload() } }) {
            if let content = model.content {
                DistanceCard(content: content, period: $model.period, formatter: formatter)
                if let pace = content.pace { PaceCard(pace: pace, formatter: formatter) }
                if let vo2 = content.vo2 { VO2Card(vo2: vo2, formatter: formatter) }
                PersonalBestsCard(rows: model.personalBests.map {
                    ProgressRunningModel.personalBestRows($0, formatter: formatter, today: container.repository.today,
                                                          calendar: container.repository.calendar)
                })
                if let load = content.load, !load.ratios.isEmpty { LoadCard(load: load, ticks: content.tickDates) }
            }
        }
        // Range, new data and a new day reload; the unit system only re-formats.
        .task(id: key) { await reload() }
        .task(id: key.dataVersion) { await model.loadPersonalBests(repository: container.repository) }
    }

    private func reload() async {
        await model.load(repository: container.repository, range: key.range)
    }
}

// MARK: - Cards

private struct DistanceCard: View {
    let content: ProgressRunningContent
    @Binding var period: ProgressPeriod
    let formatter: VigilFormatter

    var body: some View {
        let monthly = period == .monthly
        let bars = (monthly ? content.monthlyBars : content.weeklyBars).map {
            ProgressBar(id: $0.id, start: $0.start, value: formatter.displayDistance(meters: $0.value))
        }
        let goal = formatter.displayDistance(meters: monthly ? content.monthlyGoalMeters : content.weeklyGoalMeters)
        let top = max(bars.map(\.value).max() ?? 0, goal) * 1.15
        ProgressCard(title: "Distance") {
            VSegmentedControl(selection: $period, options: ProgressPeriod.allCases) { $0 == .weekly ? "Weekly" : "Monthly" }
            ProgressBigValue(
                value: formatter.distance(meters: content.totalMeters, fractionDigits: 0).text,
                caption: monthly
                    ? String(localized: "monthly totals · goal \(formatter.number(goal, fractionDigits: 0)) \(formatter.distanceUnit)")
                    : String(localized: "avg \(formatter.distance(meters: content.averageMetersPerWeek, fractionDigits: 1).text) / week"))
            if content.runCount == 0 {
                ProgressMessage(systemImage: "figure.run", text: "No runs in this range.")
            } else {
                Chart {
                    ForEach(bars) { bar in
                        BarMark(x: .value("Period", String(bar.id)), y: .value("Distance", bar.value))
                            .vBarStyle(color(for: bar, in: bars, goal: goal), cornerRadius: 5)
                    }
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.vInk)
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("Goal \(formatter.number(goal, fractionDigits: 0))")
                                .vTextStyle(.caption2).foregroundStyle(Color.vInk)
                        }
                }
                .vChartAxes()
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...top)
                .frame(height: 150)
                .accessibilityLabel(monthly ? "Distance per month" : "Distance per week")
                .accessibilityValue(progressSummary(bars.map { ProgressPoint(date: $0.start, value: $0.value) }) {
                    formatter.number($0, fractionDigits: 1) + " " + formatter.distanceUnit
                })
                ProgressTicks(dates: monthly ? content.monthTickDates : content.tickDates, format: monthly ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
            }
        }
    }

    private func color(for bar: ProgressBar, in bars: [ProgressBar], goal: Double) -> Color {
        if bar.id == bars.last?.id { return .vRun }
        return bar.value >= goal ? .vRun.opacity(0.75) : .vRunSoft
    }
}

private struct PaceCard: View {
    let pace: ProgressPaceContent
    let formatter: VigilFormatter

    var body: some View {
        let latest = formatter.pace(secondsPerKilometer: pace.latestSecondsPerKilometer)
        let change = ProgressRunningModel.paceChangeText(pace.changeSecondsPerKilometer, formatter: formatter)
        let points = pace.points.map { ProgressPoint(date: $0.date, value: formatter.displayPace(secondsPerKilometer: $0.value)) }
        ProgressCard(title: "Average pace", trailing: change?.text,
                     trailingColor: change?.isFaster == true ? .vPositive : .vInkSecondary) {
            ProgressBigValue(value: latest.value,
                             caption: String(localized: "\(latest.unit) this week · at ~\(pace.referenceHeartRate) bpm"))
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Week", point.date), y: .value("Pace", point.value)).vLineStyle(.vRun)
                }
                if let last = points.last {
                    VEndDot(x: .value("Week", last.date), y: .value("Pace", last.value), color: .vRun)
                }
            }
            .vChartAxes()
            .chartXAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .frame(height: 100)
            .accessibilityLabel("Pace at similar heart rate")
            .accessibilityValue(progressSummary(pace.points) { formatter.pace(secondsPerKilometer: $0).text })
            HStack {
                Text("slower ↓ · faster ↑")
                Spacer()
                Text("weekly average")
            }
            .vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
        }
    }
}

private struct VO2Card: View {
    let vo2: ProgressVO2Content
    let formatter: VigilFormatter

    var body: some View {
        let change = vo2.change
        ProgressCard(title: "VO₂ max",
                     trailing: change.map { String(localized: "\(signed($0)) since \(vo2.since.formatted(.dateTime.month(.abbreviated)))") },
                     trailingColor: (change ?? 0) >= 0 ? .vPositive : .vInkSecondary) {
            let latest = formatter.vo2Max(vo2.latest)
            ProgressBigValue(value: latest.value, caption: latest.unit)
            if vo2.points.count >= 2 {
                let values = vo2.points.map(\.value)
                let low = (values.min() ?? 0) - 1
                let high = (values.max() ?? 1) + 1
                Chart {
                    ForEach(vo2.points) { point in
                        AreaMark(x: .value("Date", point.date), yStart: .value("Floor", low), yEnd: .value("VO2", point.value)).vAreaStyle(.vRun)
                        LineMark(x: .value("Date", point.date), y: .value("VO2", point.value)).vLineStyle(.vRun)
                    }
                }
                .vChartAxes()
                .chartXAxis(.hidden)
                .chartYScale(domain: low...high)
                .frame(height: 90)
                .accessibilityLabel("VO₂ max trend")
                .accessibilityValue(progressSummary(vo2.points) { String(format: "%.1f", $0) })
            }
        }
    }

    private func signed(_ value: Double) -> String { formatter.signed(value, fractionDigits: 1) }
}

private struct PersonalBestsCard: View {
    let rows: [ProgressPersonalBestRow]?

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xs) {
            Text("Personal bests").vTextStyle(.headline).foregroundStyle(Color.vInk)
                .accessibilityAddTraits(.isHeader)
            if let rows {
                ForEach(rows) { row in
                    Divider().overlay(Color.vSeparator)
                    PersonalBestRow(row: row)
                }
            } else {
                ForEach(0..<3, id: \.self) { _ in
                    Divider().overlay(Color.vSeparator)
                    RoundedRectangle(cornerRadius: VRadius.bar).fill(Color.vFill).frame(height: 20).padding(.vertical, VSpacing.l)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }
}

private struct PersonalBestRow: View {
    let row: ProgressPersonalBestRow

    var body: some View {
        if let id = row.workoutID, let valueText = row.valueText {
            NavigationLink(value: AppRoute.runDetail(id)) {
                HStack(spacing: VSpacing.m) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
                        if let date = row.date { Text(dateText(date)).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary) }
                    }
                    Spacer(minLength: VSpacing.s)
                    if row.isNew {
                        Text("NEW").font(.vCustom(.body, size: 11, weight: .heavy, relativeTo: .caption2)).tracking(0.4)
                            .foregroundStyle(Color.vInkOnInverse)
                            .padding(.horizontal, VSpacing.s).frame(height: 22)
                            .background(Color.vInverseFill, in: .capsule)
                    }
                    Text(valueText).vTextStyle(.statValueSmall).foregroundStyle(Color.vInk)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.vInkTertiary).accessibilityHidden(true)
                }
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the run")
        } else {
            HStack {
                Text(row.name).vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
                Spacer()
                Text("Not run yet").vTextStyle(.subheadline).foregroundStyle(Color.vInkSecondary)
            }
            .frame(minHeight: 56)
            .accessibilityElement(children: .combine)
        }
    }

    private func dateText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? String(localized: "Today") : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private struct LoadCard: View {
    let load: ProgressLoadContent
    let ticks: [Date]

    var body: some View {
        let color: Color = switch load.risk {
        case .productive: .vPositive
        case .detraining: .vInkSecondary
        case .caution: .vWarningInk
        case .high: .vDangerInk
        }
        VStack(alignment: .leading, spacing: VSpacing.l) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Training load").vTextStyle(.headline).foregroundStyle(Color.vInk).accessibilityAddTraits(.isHeader)
                    Text("7-day ÷ 28-day load").vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    if let current = load.current { Text(current, format: .number.precision(.fractionLength(2))).vTextStyle(.title) .foregroundStyle(Color.vInk) }
                    Text(ProgressRunningModel.riskTitle(load.risk)).font(.vCustom(.body, size: 12.5, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(color)
                }
            }
            Chart {
                RectangleMark(yStart: .value("a", 1.5), yEnd: .value("b", 1.8))
                    .foregroundStyle(Color.vDangerTint)
                    .annotation(position: .overlay, alignment: .topLeading) {
                        Text("Too much, too fast · above 1.5").font(.vCustom(.body, size: 11.5, weight: .heavy, relativeTo: .caption2))
                            .foregroundStyle(Color.vDangerInk).padding(.leading, VSpacing.s).padding(.top, VSpacing.xxs)
                    }
                RectangleMark(yStart: .value("a", 0.8), yEnd: .value("b", 1.3))
                    .foregroundStyle(Color.vPositiveTint)
                    .annotation(position: .overlay, alignment: .topLeading) {
                        Text("0.8 – 1.3").font(.vCustom(.body, size: 11.5, weight: .heavy, relativeTo: .caption2))
                            .foregroundStyle(Color.vPositive).padding(.leading, VSpacing.s).padding(.top, VSpacing.xxs)
                    }
                ForEach(load.ratios) { point in
                    LineMark(x: .value("Day", point.date), y: .value("Ratio", min(max(point.value, 0.4), 1.8))).vLineStyle(.vInk)
                }
                if let last = load.ratios.last {
                    VEndDot(x: .value("Day", last.date), y: .value("Ratio", min(max(last.value, 0.4), 1.8)), color: .vInk)
                }
            }
            .vChartAxes()
            .chartXAxis(.hidden)
            .chartYScale(domain: 0.4...1.8)
            .frame(height: 150)
            .accessibilityLabel("Acute to chronic training load ratio")
            .accessibilityValue(progressSummary(load.ratios) { String(format: "%.2f", $0) })
            ProgressTicks(dates: ticks)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }
}

#Preview("Running") { ProgressRunningView(key: .preview).vigilPreview() }
#Preview("Running dark") { ProgressRunningView(key: .preview).vigilPreview().preferredColorScheme(.dark) }
#Preview("No runs") { ProgressRunningView(key: .preview).vigilPreview(.noRunsThisWeek) }
