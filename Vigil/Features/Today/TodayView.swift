import SwiftUI

/// Tab 1 · Today. Also renders the partial-data state when `overview.completeness` is `.partial`.
/// Owner: Today agent.
struct TodayView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = TodayModel()
    @State private var isPickingDate = false

    private var formatter: VigilFormatter { settingsStore.formatter }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TodayHeader(model: model, isPickingDate: $isPickingDate)
                DayStrip(items: model.stripItems(), selection: Binding(get: { model.selection }, set: { model.select($0) })) { model.step(by: $0) }
                    .padding(.top, VSpacing.xl)
                    .padding(.horizontal, VSpacing.screenGutter)
                content
                    .padding(.top, VSpacing.cardGap)
                    .padding(.horizontal, VSpacing.screenGutter)
                    .padding(.bottom, VSpacing.huge)
                    .contentShape(.rect)
                    .simultaneousGesture(swipe)
            }
        }
        .vScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await model.load(container.repository) }
        .task(id: model.selection) { await model.load(container.repository) }
        .task(id: model.window.end) { await model.loadDots(container.repository) }
        .sheet(isPresented: $isPickingDate) {
            TodayDatePickerSheet(selection: model.selection, today: model.today) { model.select($0) }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > 60, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                model.step(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .failed:
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load Today",
                           message: "Something went wrong reading your data.", actionTitle: "Try again") {
                Task { await model.load(container.repository) }
            }
            .vCard()
        case .loading, .loaded:
            let overview = model.overview ?? TodayPlaceholder.overview(day: model.selection)
            let isPlaceholder = model.overview == nil || model.isStale
            TodayContent(overview: overview, formatter: formatter, today: model.today)
                .redacted(reason: isPlaceholder ? .placeholder : [])
                .allowsHitTesting(!isPlaceholder)
                .accessibilityHidden(isPlaceholder)
        }
    }
}

/// The cards of one day.
struct TodayContent: View {
    let overview: DayOverview
    let formatter: VigilFormatter
    let today: LocalDay

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.huge - VSpacing.s) {
            VStack(spacing: VSpacing.l) {
                TodayScoreCard(overview: overview, formatter: formatter, isInProgress: isInProgress)
                banner
                if let recovery = overview.recovery {
                    TodayReadinessCard(recovery: recovery, updatedAt: overview.updatedAt, formatter: formatter)
                }
            }
            if !overview.workouts.isEmpty {
                TodayWorkoutsSection(workouts: overview.workouts, formatter: formatter)
            }
            if let activity = overview.activity {
                TodayActivityCard(activity: activity, formatter: formatter)
            }
            if overview.completeness != .none || overview.vitals.contains(where: { $0.value != nil }) {
                TodayVitalsSection(vitals: overview.vitals, day: overview.day, formatter: formatter)
            }
            TodayWeeklyCard(weekly: overview.weekly, formatter: formatter)
        }
    }

    private var isInProgress: Bool {
        overview.day == today && overview.completeness != .complete
    }

    @ViewBuilder
    private var banner: some View {
        switch overview.completeness {
        case .partial(let missing):
            if let text = TodayPresentation.partialExplanation(missing: missing, recovery: overview.recovery) {
                TodayBanner(text: text)
            }
        case .none:
            TodayBanner(text: String(localized: "Nothing was recorded for this day. Wear your Apple Watch to see scores here."),
                        systemImage: "applewatch")
        case .complete:
            EmptyView()
        }
    }
}

// MARK: - Header

struct TodayHeader: View {
    let model: TodayModel
    @Binding var isPickingDate: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: VSpacing.l) {
            VStack(alignment: .leading, spacing: VSpacing.xxxs) {
                Text(TodayPresentation.longDate(model.selection))
                    .font(.vCustom(.body, size: 15, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(.vInkSecondary)
                Text(TodayPresentation.title(for: model.selection, today: model.today))
                    .vTextStyle(.largeTitle)
                    .foregroundStyle(.vInk)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            HStack(spacing: VSpacing.xs) {
                CircleIconButton(systemImage: "chevron.left", label: "Previous day") { model.step(by: -1) }
                CircleIconButton(systemImage: "calendar", label: "Choose a date") { isPickingDate = true }
                CircleIconButton(systemImage: "chevron.right", label: "Next day", isDisabled: !model.canStepForward) { model.step(by: 1) }
            }
        }
        .padding(.horizontal, VSpacing.headerGutter)
        .padding(.top, VSpacing.s)
    }
}

struct TodayDatePickerSheet: View {
    let selection: LocalDay
    let today: LocalDay
    let onPick: (LocalDay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(selection: LocalDay, today: LocalDay, onPick: @escaping (LocalDay) -> Void) {
        self.selection = selection
        self.today = today
        self.onPick = onPick
        _date = State(initialValue: selection.startDate())
    }

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, in: ...today.interval().end.addingTimeInterval(-1), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal, VSpacing.screenGutter)
                .navigationTitle("Choose a date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onPick(LocalDay(date)); dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Placeholder

/// Plausible content shown redacted while the first load runs.
enum TodayPlaceholder {
    static func overview(day: LocalDay) -> DayOverview {
        let factors = RecoveryFactorKind.allCases.map { RecoveryFactor(kind: $0, value: 60, baseline: 58, points: 3, isAvailable: true) }
        let recovery = RecoveryScore(value: 72, band: .green, factors: factors, suggestion: .push,
                                     message: "Loading your readiness for the day, one moment.", suggestedStrain: 50...70,
                                     signalsUsed: 5, signalsTotal: 5)
        let vitals = HealthMetric.vitals.map {
            VitalReading(metric: $0, value: 60, baseline: Baseline(mean: 58, standardDeviation: 4, sampleCount: 30), delta: 2,
                         deltaPercent: 3, status: .within, trend: [])
        }
        let weekly = WeeklyProgress(startDay: day.adding(days: -6), endDay: day, runDistanceMeters: 10_000, runGoalMeters: 25_000, runCount: 2,
                                    runDuration: 3_000, dailyRunDistanceMeters: Array(repeating: 0, count: 7), liftSessions: 1, liftGoal: 3,
                                    liftDuration: 3_000, liftEnergyKilocalories: 300, dailyTrainingKinds: Array(repeating: [], count: 7),
                                    averageSleep: 7 * 3_600, sleepTarget: 8 * 3_600)
        return DayOverview(day: day, recovery: recovery, sleepNight: nil,
                           sleepScore: SleepScore(value: 80, band: .good, contributors: [], targetDifference: 0),
                           strain: DailyStrain(day: day, value: 50, level: .moderate, workouts: [], everydayMovement: 10,
                                               zoneDurations: ZoneDurations(), trainingLoad: 0),
                           activity: DailyActivity(day: day, steps: 8_000, activeEnergyKilocalories: 500, basalEnergyKilocalories: nil,
                                                   exerciseMinutes: 30, standHours: 9,
                                                   goals: ActivityGoals(moveKilocalories: 600, exerciseMinutes: 30, standHours: 12)),
                           vitals: vitals, workouts: [], weekly: weekly, completeness: .complete, updatedAt: .now)
    }
}

#Preview { TodayView().vigilPreview() }
#Preview("Partial data") { TodayView().vigilPreview(.partialData) }
#Preview("Low recovery") { TodayView().vigilPreview(.lowRecovery) }
#Preview("New user") { TodayView().vigilPreview(.newUser) }
#Preview("Dark") { TodayView().vigilPreview().preferredColorScheme(.dark) }
