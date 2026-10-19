import SwiftUI

/// Train · Lift: weekly sessions vs. goal and the paginated list of strength workouts.
struct TrainLiftView: View {
    let model: TrainModel
    @Environment(AppContainer.self) private var container

    var body: some View {
        if let weekly = model.weekly {
            TrainLiftWeekCard(weekly: weekly, calendar: model.calendar)
            if weekly.liftSessions == 0 { TrainNoLiftsCard() }
            Label("Vigil shows workout-level data from Health. Sets, reps and weights stay in your lifting app.",
                  systemImage: "info.circle")
                .vTextStyle(.footnote)
                .foregroundStyle(Color.vInkLabel)
                .labelStyle(TrainInfoLabelStyle())
                .padding(.horizontal, VSpacing.s)
            if !model.lifts.items.isEmpty { list }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: VSpacing.m) {
            SectionHeader("Strength workouts").padding(.top, VSpacing.l)
            ForEach(model.lifts.groups) { group in
                Text(TrainFormatting.monthTitle(group.start, now: model.now, calendar: model.calendar))
                    .vTextStyle(.overline)
                    .foregroundStyle(Color.vInkSecondary)
                    .padding(.horizontal, VSpacing.xxs)
                    .padding(.top, VSpacing.xs)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.items) { lift in
                    NavigationLink(value: AppRoute.liftDetail(lift.id)) {
                        TrainLiftRow(lift: lift, model: model)
                    }
                    .buttonStyle(.vPress)
                    .onAppear {
                        if lift.id == model.lifts.items.last?.id {
                            Task { await model.loadMore(.strength, repository: container.repository) }
                        }
                    }
                }
            }
            if model.lifts.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, VSpacing.l)
            }
        }
    }
}

private struct TrainInfoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: VSpacing.s) {
            configuration.icon.font(.system(size: 14, weight: .semibold)).padding(.top, 2)
            configuration.title
        }
    }
}

/// "Last 7 days" card for lifting.
struct TrainLiftWeekCard: View {
    let weekly: WeeklyProgress
    let calendar: Calendar
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let formatter = settingsStore.formatter
        let initials = TrainFormatting.weekdayInitials(start: weekly.startDay, count: weekly.dailyTrainingKinds.count, calendar: calendar)
        TrainCard(title: "Last 7 days",
                  trailing: TrainFormatting.weekRange(start: weekly.startDay, end: weekly.endDay, calendar: calendar)) {
            HStack(spacing: VSpacing.xxl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions").font(.vCustom(.body, size: 12.5, weight: .semibold, relativeTo: .caption)).foregroundStyle(Color.vInkSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                        Text("\(weekly.liftSessions)").vTextStyle(.score).foregroundStyle(Color.vInk)
                            .minimumScaleFactor(0.6)
                        Text("of \(weekly.liftGoal)").vTextStyle(.callout).foregroundStyle(Color.vInkSecondary)
                    }
                }
                HStack(spacing: VSpacing.xs) {
                    ForEach(0..<max(weekly.liftGoal, 1), id: \.self) { index in
                        Capsule().fill(index < weekly.liftSessions ? Color.vLift : Color.vFill).frame(height: 12)
                    }
                }
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sessions")
            .accessibilityValue("\(weekly.liftSessions) of \(weekly.liftGoal)")
            HStack(spacing: VSpacing.m) {
                TrainTile(label: "Total time", value: formatter.duration(weekly.liftDuration, style: .hoursMinutes))
                TrainTile(label: "Calories", value: formatter.energy(kilocalories: weekly.liftEnergyKilocalories).value,
                          unit: formatter.energy(kilocalories: weekly.liftEnergyKilocalories).unit)
            }
            HStack(spacing: VSpacing.xs) {
                ForEach(initials.indices, id: \.self) { index in
                    let kinds = weekly.dailyTrainingKinds[index]
                    let isLift = kinds.contains(.strength)
                    let isRun = kinds.contains(.run)
                    VStack(spacing: VSpacing.xs) {
                        Image(systemName: isLift ? "dumbbell.fill" : (isRun ? "figure.run" : "minus"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isLift ? Color.vInkOnAccent : (isRun ? Color.vRun : Color.vInkTertiary))
                            .frame(width: 34, height: 34)
                            .background(isLift ? Color.vLift : (isRun ? Color.vRunTint : Color.vBackground), in: .circle)
                        Text(initials[index]).font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption)).foregroundStyle(Color.vInkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(initials[index])
                    .accessibilityValue(isLift ? "Lift" : (isRun ? "Run" : "Rest"))
                }
            }
        }
    }
}

/// Inset stat tile on the raised card colour.
struct TrainTile: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String?

    var body: some View {
        TrainValueCell(label: label, value: value, unit: unit)
            .padding(.horizontal, VSpacing.cardPaddingCompact)
            .padding(.vertical, VSpacing.l)
            .background(Color.vCardRaised, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
    }
}

/// Dashed inline empty state for "no lifts this week".
struct TrainNoLiftsCard: View {
    var body: some View {
        VStack(spacing: VSpacing.m) {
            Image(systemName: "dumbbell")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.vLift)
                .frame(width: 56, height: 56)
                .background(Color.vLiftTint, in: .rect(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text("No strength workouts this week").vTextStyle(.title2).foregroundStyle(Color.vInk).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Workouts from Hevy, your Apple Watch, or any app that saves to Health appear here on their own.")
                .vTextStyle(.callout).foregroundStyle(Color.vInkLabel).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: VRadius.cardLarge, style: .continuous)
            .strokeBorder(Color.vInkDisabled, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        .accessibilityElement(children: .combine)
    }
}

/// One strength workout in the list.
struct TrainLiftRow: View {
    let lift: WorkoutSummary
    let model: TrainModel
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let formatter = settingsStore.formatter
        let workout = lift.workout
        let date = TrainFormatting.rowDate(workout.start, style: .lift, now: model.now, calendar: model.calendar, formatter: formatter)
        let energy = (workout.activeEnergyKilocalories ?? workout.totalEnergyKilocalories).map { formatter.energy(kilocalories: $0) }
        VStack(spacing: VSpacing.l) {
            HStack(spacing: VSpacing.l) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.vStrainInk)
                    .frame(width: 42, height: 42)
                    .background(Color.vLiftTint, in: .rect(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.displayName).vTextStyle(.body).fontWeight(.bold).foregroundStyle(Color.vInk).lineLimit(1)
                    Text(date).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary).lineLimit(1)
                }
                Spacer(minLength: VSpacing.xs)
                VChip(LocalizedStringKey(workout.source.name))
            }
            Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline)
            HStack(alignment: .top) {
                TrainLiftMetric(value: formatter.duration(workout.duration, style: .minutes), label: String(localized: "duration"))
                TrainLiftMetric(value: energy?.value ?? "–", label: energy?.unit ?? "kcal")
                TrainLiftMetric(value: workout.averageHeartRate.map { formatter.heartRate(bpm: $0).value } ?? "–", label: String(localized: "avg bpm"))
            }
        }
        .padding(.horizontal, VSpacing.xxl)
        .padding(.vertical, VSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
        .shadow(color: .vShadow, radius: 1, y: 1)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(workout.displayName), \(date), from \(workout.source.name)")
        .accessibilityValue([formatter.duration(workout.duration, style: .minutes), energy?.text,
                             workout.averageHeartRate.map { formatter.heartRate(bpm: $0).text }]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

private struct TrainLiftMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).vTextStyle(.body).fontWeight(.bold).foregroundStyle(Color.vInk).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).vTextStyle(.caption).foregroundStyle(Color.vInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
