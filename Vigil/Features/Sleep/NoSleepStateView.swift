import SwiftUI

/// State · No sleep recorded. `SleepView` shows the same card inline; this standalone screen is
/// reachable from the state gallery and keeps the calendar, prior-night and debt links.
struct NoSleepStateView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var debt: SleepDebt?
    @State private var nightBefore: LocalDay?

    private var repository: VigilRepository { container.repository }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.xl) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: VSpacing.xxxs) {
                        Text(SleepFormat.nightRange(for: repository.today, calendar: repository.calendar))
                            .vTextStyle(.bodyStrong).foregroundStyle(Color.vNightInkSecondary)
                        Text("Last night").vTextStyle(.largeTitle).foregroundStyle(Color.vNightInk)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    if let nightBefore {
                        NavigationLink(value: AppRoute.sleepNight(nightBefore)) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.vNightInk)
                                .frame(width: VSize.minTapTarget, height: VSize.minTapTarget)
                                .background(Color.vNightCardRaised, in: .circle)
                        }
                        .buttonStyle(.vPress)
                        .accessibilityLabel("Previous night")
                    }
                    NavigationLink(value: AppRoute.sleepCalendar(repository.today)) {
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.vNightInk)
                            .frame(width: VSize.minTapTarget, height: VSize.minTapTarget)
                            .background(Color.vNightCardRaised, in: .circle)
                    }
                    .buttonStyle(.vPress)
                    .accessibilityLabel("Sleep calendar")
                }
                .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
                SleepNoSleepCard(nightBefore: nightBefore)
                if let debt { SleepDebtSummaryRow(debt: debt, formatter: settingsStore.formatter) }
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .vNightScreen()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let today = repository.today
            debt = try? await repository.sleepDebt(endingOn: today)
            let start = today.adding(days: -30, calendar: repository.calendar)
            let history = (try? await repository.sleepHistory(from: start, through: today)) ?? []
            nightBefore = history.last { $0.day < today && $0.asleep != nil }?.day
        }
    }
}

#Preview {
    NoSleepStateView().vigilPreview(.noSleepLastNight)
}
