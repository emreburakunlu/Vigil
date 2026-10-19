import SwiftUI

/// Sleep calendar for the month containing `month`.
struct SleepCalendarView: View {
    let month: LocalDay

    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = SleepCalendarModel()
    @State private var first: LocalDay?

    private var repository: VigilRepository { container.repository }
    private var calendar: Calendar { repository.calendar }
    private var shownFirst: LocalDay { first ?? SleepCalendarMonth.firstOfMonth(month) }
    private var currentFirst: LocalDay { SleepCalendarMonth.firstOfMonth(repository.today) }
    /// Earliest month reachable (two years back).
    private var earliestFirst: LocalDay { SleepCalendarMonth.month(currentFirst, offset: -24, calendar: calendar) }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.xl) {
                monthSwitcher
                if let data = model.month, data.first == shownFirst {
                    gridCard(data)
                    summary(data.summary)
                } else if model.failed {
                    SleepFailedView { Task { await reload() } }
                } else {
                    RoundedRectangle(cornerRadius: VRadius.cardLarge, style: .continuous)
                        .fill(Color.vNightCard).frame(height: 420)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .vNightScreen()
        .navigationTitle("Sleep calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shownFirst) { await reload() }
    }

    private func reload() async {
        await model.load(repository: repository, first: shownFirst, selected: month)
    }

    private var monthSwitcher: some View {
        HStack {
            CircleIconButton(systemImage: "chevron.left",
                             label: LocalizedStringKey(SleepFormat.monthTitle(SleepCalendarMonth.month(shownFirst, offset: -1, calendar: calendar), calendar: calendar)),
                             isDisabled: shownFirst <= earliestFirst) {
                first = SleepCalendarMonth.month(shownFirst, offset: -1, calendar: calendar)
            }
            Spacer()
            Text(SleepFormat.monthTitle(shownFirst, calendar: calendar))
                .vTextStyle(.title).foregroundStyle(Color.vNightInk)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            CircleIconButton(systemImage: "chevron.right",
                             label: LocalizedStringKey(SleepFormat.monthTitle(SleepCalendarMonth.month(shownFirst, offset: 1, calendar: calendar), calendar: calendar)),
                             isDisabled: shownFirst >= currentFirst) {
                first = SleepCalendarMonth.month(shownFirst, offset: 1, calendar: calendar)
            }
        }
        .padding(.top, VSpacing.s)
    }

    private func gridCard(_ data: SleepCalendarMonth) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let order = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        return VStack(spacing: VSpacing.xs) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(order.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).vTextStyle(.caption).fontWeight(.heavy).foregroundStyle(Color.vNightInkSecondary)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: VSpacing.xs) {
                ForEach(data.cells) { cell in SleepCalendarCell(cell: cell, calendar: calendar) }
            }
            legend.padding(.top, VSpacing.l)
        }
        .padding(.horizontal, VSpacing.s)
        .vNightCard(padding: VSpacing.xl, radius: VRadius.cardLarge)
        .accessibilityElement(children: .contain)
    }

    private var legend: some View {
        let bands: [SleepScoreBand] = [.great, .good, .fair, .poor]
        return HStack(spacing: VSpacing.xl) {
            ForEach(bands, id: \.self) { band in
                HStack(spacing: VSpacing.xs) {
                    Circle().fill(Color.vSleepScoreBand(band)).frame(width: 10, height: 10)
                    Text(band.legend).vTextStyle(.caption).foregroundStyle(Color.vNightInkLabel)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    private func summary(_ s: SleepCalendarMonth.Summary) -> some View {
        let formatter = settingsStore.formatter
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: VSpacing.m), GridItem(.flexible())], spacing: VSpacing.m) {
            summaryTile("Average score", value: s.averageScore.map { "\($0)" } ?? "–")
            summaryTile("Average asleep", value: s.averageAsleep.map { formatter.duration($0) } ?? "–")
            summaryTile("Nights at target", value: "\(s.nightsAtTarget)", unit: String(localized: "of \(s.recordedNights)"))
            summaryTile("Best night", value: s.bestScore.map { "\($0)" } ?? "–",
                        unit: s.bestDay.map { SleepFormat.shortDate($0, calendar: calendar) })
        }
    }

    private func summaryTile(_ title: LocalizedStringKey, value: String, unit: String? = nil) -> some View {
        StatTile(title, value: value, unit: unit)
            .padding(VSpacing.cardPaddingCompact)
            .background(Color.vNightCard, in: .rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.vNightSeparator, lineWidth: VSize.hairline))
    }
}

/// One day of the calendar grid.
struct SleepCalendarCell: View {
    let cell: SleepCalendarMonth.Cell
    let calendar: Calendar

    @ScaledMetric(relativeTo: .caption) private var ring: CGFloat = 34

    var body: some View {
        switch cell.kind {
        case .blank:
            Color.clear.frame(height: ring + 30)
        case .scored(let score):
            if let day = cell.day {
                NavigationLink(value: AppRoute.sleepNight(day)) {
                    VStack(spacing: 3) {
                        dayNumber(day, selected: cell.isSelected)
                        ScoreRing(progress: Double(score) / 100, color: .vSleepScoreBand(SleepScoreBand(score: score)),
                                  track: .vNightFill, diameter: ring, animated: false) {
                            Text("\(score)").font(.vCustom(.body, size: 11.5, weight: .heavy, relativeTo: .caption2))
                                .foregroundStyle(Color.vNightInk).minimumScaleFactor(0.6)
                        }
                    }
                    .padding(.vertical, VSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(cell.isSelected ? Color.vNightSelected : .clear, in: .rect(cornerRadius: 14, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(SleepFormat.spokenDate(day, calendar: calendar)), sleep score \(score)")
            }
        case .missing, .future:
            if let day = cell.day {
                let missing = cell.kind == .missing
                VStack(spacing: 3) {
                    Text("\(day.day)").vTextStyle(.caption).fontWeight(.bold)
                        .foregroundStyle(missing ? Color.vNightInkSecondary : Color.vNightInkTertiary.opacity(0.7))
                    Circle()
                        .strokeBorder(missing ? Color.vNightDashed : Color.vNightSeparator, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        .frame(width: ring, height: ring)
                        .overlay { if missing { Text("—").vTextStyle(.caption2).foregroundStyle(Color.vNightInkTertiary) } }
                }
                .padding(.vertical, VSpacing.xs)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(missing
                    ? "\(SleepFormat.spokenDate(day, calendar: calendar)), no sleep recorded"
                    : "\(SleepFormat.spokenDate(day, calendar: calendar))")
            }
        }
    }

    private func dayNumber(_ day: LocalDay, selected: Bool) -> some View {
        Text("\(day.day)").vTextStyle(.caption).fontWeight(.bold)
            .foregroundStyle(selected ? Color.vNightInk : Color.vNightInkLabel)
    }
}

#Preview {
    SleepCalendarView(month: .today()).vigilPreview()
}

#Preview("Dark") {
    SleepCalendarView(month: .today()).vigilPreview().preferredColorScheme(.dark)
}
