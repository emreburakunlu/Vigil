import SwiftUI

/// Tab 2 · Sleep (night palette). Shows the no-sleep state when the selected night is missing.
/// Owner: Sleep agent.
struct SleepView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = SleepModel()
    @State private var selectedDay: LocalDay?

    private var repository: VigilRepository { container.repository }
    private var today: LocalDay { repository.today }
    private var day: LocalDay { selectedDay ?? today }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.xl) {
                header
                content
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .vNightScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: day) {
            await model.loadNight(repository: repository, formatter: settingsStore.formatter, day: day)
        }
        .task(id: today) {
            await model.loadTrends(repository: repository, formatter: settingsStore.formatter)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: VSpacing.l) {
            VStack(alignment: .leading, spacing: VSpacing.xxxs) {
                Text(SleepFormat.nightRange(for: day, calendar: repository.calendar))
                    .vTextStyle(.bodyStrong).foregroundStyle(Color.vNightInkSecondary)
                Text(day == today ? "Last night" : LocalizedStringKey(SleepFormat.weekdayTitle(for: day, calendar: repository.calendar)))
                    .vTextStyle(.largeTitle).foregroundStyle(Color.vNightInk)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: VSpacing.s)
            HStack(spacing: VSpacing.xs) {
                CircleIconButton(systemImage: "chevron.left", label: "Previous night") {
                    selectedDay = day.adding(days: -1, calendar: repository.calendar)
                }
                NavigationLink(value: AppRoute.sleepCalendar(day)) {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.vNightInk)
                        .frame(width: VSize.minTapTarget, height: VSize.minTapTarget)
                        .background(Color.vNightCardRaised, in: .circle)
                        .overlay(Circle().strokeBorder(Color.vNightSeparator, lineWidth: VSize.hairline))
                        .contentShape(.circle)
                }
                .buttonStyle(.vPress)
                .accessibilityLabel("Sleep calendar")
                CircleIconButton(systemImage: "chevron.right", label: "Next night", isDisabled: day >= today) {
                    let next = day.adding(days: 1, calendar: repository.calendar)
                    selectedDay = next >= today ? nil : next
                }
            }
        }
        .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
        .padding(.top, VSpacing.s)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            SleepSkeleton()
        case .failed:
            SleepFailedView {
                Task { await model.loadNight(repository: repository, formatter: settingsStore.formatter, day: day) }
            }
        case .empty:
            SleepNoSleepCard(isLastNight: day == today, nightBefore: model.previousRecordedDay(before: day))
            if let debt = model.debt { SleepDebtSummaryRow(debt: debt, formatter: settingsStore.formatter) }
        case .loaded(let night):
            SleepScoreCard(night: night)
            SleepStagesCard(night: night)
            if night.hasVitals { SleepVitalsCard(night: night) }
            if let debt = model.debt {
                SleepDebtCard(debt: debt, formatter: settingsStore.formatter, calendar: repository.calendar)
            }
            trends
            SleepInsightsSection(items: model.insights)
        }
    }

    @ViewBuilder
    private var trends: some View {
        if model.chart != nil { SleepTrendsCard(model: model) }
    }
}

#Preview {
    SleepView().vigilPreview()
}

#Preview("No sleep") {
    SleepView().vigilPreview(.noSleepLastNight)
}
