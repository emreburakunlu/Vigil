import SwiftUI

/// Train · Run: weekly distance card, 7-day chart and the paginated list of runs
/// (shows `NoRunsStateView` when nothing was run in the last 7 days).
struct TrainRunView: View {
    let model: TrainModel
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        if let weekly = model.weekly {
            TrainRunWeekCard(weekly: weekly, calendar: model.calendar)
            if weekly.runCount == 0 {
                NoRunsStateView(lastRun: model.lastRun)
            }
            if weekly.runCount > 0, !model.runs.items.isEmpty {
                runList
            }
        }
    }

    @ViewBuilder private var runList: some View {
        Group {
            SectionHeader("Runs", trailing: "From Apple Health")
                .padding(.top, VSpacing.xl)
            ForEach(model.runs.items) { run in
                NavigationLink(value: AppRoute.runDetail(run.id)) {
                    TrainRunRow(run: run, model: model)
                }
                .buttonStyle(.vPress)
                .onAppear {
                    if run.id == model.runs.items.last?.id {
                        Task { await model.loadMore(.run, repository: container.repository) }
                    }
                }
            }
            if model.runs.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, VSpacing.l)
            }
        }
    }
}

/// "Last 7 days" card: distance vs goal, time, runs, goal bar and the 7-day distance bars.
struct TrainRunWeekCard: View {
    let weekly: WeeklyProgress
    let calendar: Calendar
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let formatter = settingsStore.formatter
        let distance = formatter.distance(meters: weekly.runDistanceMeters, fractionDigits: 1)
        let goal = formatter.distance(meters: weekly.runGoalMeters, fractionDigits: 0)
        let fraction = weekly.runGoalMeters > 0 ? weekly.runDistanceMeters / weekly.runGoalMeters : 0
        let days = TrainFormatting.weekdayInitials(start: weekly.startDay, count: weekly.dailyRunDistanceMeters.count, calendar: calendar)
        let names = TrainFormatting.weekdayNames(start: weekly.startDay, count: weekly.dailyRunDistanceMeters.count, calendar: calendar)
        let bars = TrainFormatting.barFractions(weekly.dailyRunDistanceMeters)
        TrainCard(title: "Last 7 days",
                  trailing: TrainFormatting.weekRange(start: weekly.startDay, end: weekly.endDay, calendar: calendar),
                  spacing: VSpacing.xxl) {
            HStack(alignment: .top, spacing: VSpacing.s) {
                StatTile("Distance", value: distance.value, unit: "/ \(goal.text)")
                StatTile("Time", value: formatter.duration(weekly.runDuration, style: .hoursMinutesClock))
                StatTile("Runs", value: "\(weekly.runCount)")
            }
            VProgressTrack(fraction: fraction, color: .vRun)
                .accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: VSpacing.m) {
                ForEach(days.indices, id: \.self) { index in
                    let meters = weekly.dailyRunDistanceMeters[index]
                    VStack(spacing: VSpacing.xs) {
                        Spacer(minLength: 0)
                        Text(meters > 0 ? formatter.number(formatter.displayDistance(meters: meters), fractionDigits: 1) : " ")
                            .font(.vCustom(.body, size: 11.5, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(Color.vInkLabel)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(meters <= 0 ? Color.vControlTrack : (index == days.count - 1 ? Color.vRun : Color.vRunSoft))
                            .frame(height: max(4, 70 * bars[index]))
                        Text(days[index])
                            .font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption))
                            .foregroundStyle(Color.vInkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(names[index])
                    .accessibilityValue(meters > 0 ? formatter.distance(meters: meters).text : String(localized: "Rest day"))
                }
            }
            .frame(height: bars.contains { $0 > 0 } ? 110 : 40)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One run in the list: route thumbnail, name, date, distance / time / pace / HR.
struct TrainRunRow: View {
    let run: WorkoutSummary
    let model: TrainModel
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let formatter = settingsStore.formatter
        let workout = run.workout
        let distance = workout.distanceMeters.map { formatter.distance(meters: $0) }
        let pace = workout.averagePaceSecondsPerKilometer.map { formatter.pace(secondsPerKilometer: $0) }
        let date = TrainFormatting.rowDate(workout.start, style: .run, now: model.now, calendar: model.calendar, formatter: formatter)
        HStack(alignment: .top, spacing: VSpacing.xl) {
            TrainRouteThumbnail(workout: workout, cache: model.routeCache)
            VStack(alignment: .leading, spacing: VSpacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                    Text(workout.displayName).vTextStyle(.bodyStrong).foregroundStyle(Color.vInk).lineLimit(1)
                    Spacer(minLength: VSpacing.xs)
                    Text(date).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary).lineLimit(1)
                }
                TrainRunMetricsLayout(spacing: VSpacing.xxs) {
                    TrainRunMetric(value: distance?.value ?? "–", unit: distance?.unit ?? formatter.distanceUnit)
                    TrainRunMetric(value: formatter.duration(workout.duration, style: .clock), unit: String(localized: "time"))
                    TrainRunMetric(value: pace?.value ?? "–:––", unit: pace?.unit ?? formatter.paceUnit)
                    TrainRunMetric(value: workout.averageHeartRate.map { formatter.heartRate(bpm: $0).value } ?? "–", unit: formatter.heartRate(bpm: 0).unit)
                }
            }
        }
        .padding(VSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
        .shadow(color: .vShadow, radius: 1, y: 1)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(workout.displayName), \(date)")
        .accessibilityValue(summary(distance: distance, pace: pace, formatter: formatter))
        .accessibilityAddTraits(.isButton)
    }

    private func summary(distance: FormattedValue?, pace: FormattedValue?, formatter: VigilFormatter) -> String {
        [distance?.text, formatter.duration(run.workout.duration, style: .clock), pace?.text,
         run.workout.averageHeartRate.map { formatter.heartRate(bpm: $0).text }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// Four columns weighted 1 : 1.35 : 1 : 0.8 (distance, time, pace, heart rate) so H:MM:SS times fit.
private struct TrainRunMetricsLayout: Layout {
    var spacing: CGFloat
    private let weights: [CGFloat] = [1, 1.35, 1, 0.8]

    private func widths(total: CGFloat, count: Int) -> [CGFloat] {
        let used = weights.prefix(count)
        let available = total - spacing * CGFloat(max(count - 1, 0))
        let sum = used.reduce(0, +)
        return used.map { available * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 280
        let columnWidths = widths(total: total, count: subviews.count)
        let height = zip(subviews, columnWidths).map { $0.sizeThatFits(.init(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(total: bounds.width, count: subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: .init(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

private struct TrainRunMetric: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).vTextStyle(.body).fontWeight(.bold).foregroundStyle(Color.vInk).lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.vCustom(.body, size: 11.5, weight: .semibold, relativeTo: .caption2)).foregroundStyle(Color.vInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
