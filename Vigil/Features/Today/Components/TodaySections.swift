import SwiftUI

// MARK: - Workouts

struct TodayWorkoutsSection: View {
    let workouts: [WorkoutSummary]
    let formatter: VigilFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            SectionHeader("Today's workouts", trailing: "From Apple Health")
            ForEach(workouts) { item in
                let display = TodayPresentation.workout(item, formatter: formatter)
                switch item.workout.kind {
                case .run:
                    NavigationLink(value: AppRoute.runDetail(item.id)) { TodayWorkoutRow(display: display) }.buttonStyle(.vPress)
                case .strength:
                    NavigationLink(value: AppRoute.liftDetail(item.id)) { TodayWorkoutRow(display: display) }.buttonStyle(.vPress)
                case .other:
                    TodayWorkoutRow(display: display)
                }
            }
        }
    }
}

struct TodayWorkoutRow: View {
    let display: TodayPresentation.WorkoutDisplay
    @Environment(\.dynamicTypeSize) private var typeSize

    private var icon: (name: String, fg: Color, bg: Color) {
        switch display.kind {
        case .run: ("figure.run", .vRun, .vRunTint)
        case .strength: ("dumbbell.fill", .vStrainInk, .vLiftTint)
        case .other: ("figure.mixed.cardio", .vInkLabel, .vFill)
        }
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: VSpacing.s)) : AnyLayout(HStackLayout(spacing: VSpacing.xl))
        layout {
            Image(systemName: icon.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(icon.fg)
                .frame(width: 56, height: 56)
                .background(icon.bg, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(display.title).vTextStyle(.bodyStrong).font(.vCustom(.body, size: 16, weight: .bold, relativeTo: .body)).foregroundStyle(.vInk)
                Text(display.subtitle).font(.vCustom(.body, size: 13.5, weight: .medium, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if display.trailingPrimary != nil || display.trailingSecondary != nil {
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    if let primary = display.trailingPrimary {
                        Text(primary).font(.vCustom(.heading, size: 20, weight: .bold, relativeTo: .headline)).foregroundStyle(.vInk)
                    }
                    if let secondary = display.trailingSecondary {
                        Text(secondary).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
                    }
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard(padding: VSpacing.cardPaddingCompact, radius: 22)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Activity

struct TodayActivityRings: View {
    let move: Double
    let exercise: Double
    let stand: Double

    private let stroke: CGFloat = 11

    var body: some View {
        ZStack {
            ring(move, .vMove, .vMoveTint, diameter: 112)
            ring(exercise, .vExercise, .vExerciseTint, diameter: 86)
            ring(stand, .vStand, .vStandTint, diameter: 60)
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
    }

    private func ring(_ value: Double, _ color: Color, _ track: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(stroke / 2)
        .frame(width: diameter, height: diameter)
    }
}

struct TodayActivityCard: View {
    let activity: DailyActivity
    let formatter: VigilFormatter
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            SectionHeader("Activity")
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: VSpacing.xxl)) : AnyLayout(HStackLayout(spacing: 18))
            layout {
                TodayActivityRings(move: activity.moveProgress ?? 0, exercise: activity.exerciseProgress ?? 0, stand: activity.standProgress ?? 0)
                StatGrid(columns: 2, spacing: VSpacing.m) {
                    StatTile("Steps", value: formatter.steps(activity.steps), style: .compact)
                    StatTile("Move", value: formatter.number(activity.activeEnergyKilocalories, fractionDigits: 0),
                             unit: activity.goals.map { "/\(formatter.number($0.moveKilocalories, fractionDigits: 0)) kcal" } ?? "kcal", style: .compact)
                    StatTile("Exercise", value: formatter.number(activity.exerciseMinutes, fractionDigits: 0),
                             unit: activity.goals.map { "/\(formatter.number($0.exerciseMinutes, fractionDigits: 0)) min" } ?? "min", style: .compact)
                    StatTile("Stand", value: "\(activity.standHours)", unit: activity.goals.map { "/\($0.standHours) h" } ?? "h", style: .compact)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard(radius: 22)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(activityLabel)
        }
    }

    private var activityLabel: Text {
        guard activity.goals != nil else { return Text("Activity") }
        func pct(_ v: Double?) -> Int { Int(((v ?? 0) * 100).rounded()) }
        return Text("Activity rings: Move \(pct(activity.moveProgress)) percent, Exercise \(pct(activity.exerciseProgress)) percent, Stand \(pct(activity.standProgress)) percent")
    }
}

// MARK: - Vitals

struct TodayVitalsSection: View {
    let vitals: [VitalReading]
    let day: LocalDay
    let formatter: VigilFormatter

    private var displays: [TodayPresentation.VitalDisplay] {
        vitals.map { TodayPresentation.vital($0, formatter: formatter) }
            // Blood oxygen is optional hardware: only listed when recorded.
            .filter { $0.isRecorded || $0.metric != .oxygenSaturation }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            SectionHeader("Vitals", trailing: "vs. 30-day baseline")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: VSpacing.m), GridItem(.flexible(), spacing: VSpacing.m)], spacing: VSpacing.m) {
                ForEach(displays) { vital in
                    if vital.isRecorded {
                        NavigationLink(value: AppRoute.metric(vital.metric, day)) {
                            VitalTile(name: LocalizedStringKey(vital.metric.shortName), value: vital.value ?? "–", unit: vital.unit,
                                      delta: vital.delta.map { DeltaBadge($0.text, direction: $0.direction, tone: $0.tone) },
                                      trend: vital.trend, trendColor: sparkColor(vital.tone))
                        }
                        .buttonStyle(.vPress)
                    } else {
                        TodayMissingVitalTile(name: vital.metric.shortName)
                    }
                }
            }
        }
    }

    private func sparkColor(_ tone: VDeltaTone) -> Color {
        switch tone {
        case .positive: .vRecovery
        case .caution: .vWarning
        case .neutral: .vInkTertiary
        }
    }
}

struct TodayMissingVitalTile: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Text(name).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
            Text("—").font(.vCustom(.heading, size: 26, weight: .bold, relativeTo: .title)).foregroundStyle(.vInkTertiary)
            Text("Not recorded").font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
        }
        .padding(VSpacing.cardPaddingCompact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.vInkDisabled, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), not recorded"))
    }
}

// MARK: - Weekly

struct TodayWeeklyCard: View {
    let weekly: WeeklyProgress
    let formatter: VigilFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            SectionHeader("Last 7 days", trailing: LocalizedStringKey(TodayPresentation.weekRange(weekly)))
            VStack(alignment: .leading, spacing: VSpacing.xxl) {
                ProgressBarGoal("Running", value: weekly.runDistanceMeters, goal: weekly.runGoalMeters,
                                valueText: formatter.distance(meters: weekly.runDistanceMeters, fractionDigits: 1).value,
                                goalText: "/ " + formatter.distance(meters: weekly.runGoalMeters, fractionDigits: 0).text, color: .vRun)
                SegmentedGoalBar(title: "Lifting", done: weekly.liftSessions, goal: weekly.liftGoal, valueText: "\(weekly.liftSessions)",
                                 goalText: "/ \(weekly.liftGoal) sessions", color: .vLift)
                ProgressBarGoal("Average sleep", value: weekly.averageSleep ?? 0, goal: weekly.sleepTarget,
                                valueText: weekly.averageSleep.map { formatter.duration($0) } ?? "–",
                                goalText: "/ " + TodayPresentation.compactDuration(weekly.sleepTarget, formatter: formatter), color: .vSleep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard(radius: 22)
        }
    }
}
