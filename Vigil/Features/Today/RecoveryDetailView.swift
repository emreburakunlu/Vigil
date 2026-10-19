import Charts
import SwiftUI

/// State of the Recovery detail screen.
@MainActor
@Observable
final class RecoveryDetailModel {
    enum Phase: Equatable { case loading, loaded, failed }

    private(set) var phase: Phase = .loading
    private(set) var overview: DayOverview?
    /// Recovery values for the 30 days ending on `day`, oldest first (days without a score are absent).
    private(set) var history: [(day: LocalDay, value: Int)] = []
    private(set) var hrv: MetricSeries?
    private(set) var restingHeartRate: MetricSeries?
    private(set) var today: LocalDay

    var day: LocalDay

    init(day: LocalDay, today: LocalDay = .today()) {
        self.day = day
        self.today = today
    }

    var canStepForward: Bool { day < today }
    var isStale: Bool { overview?.day != day }

    func step(by delta: Int) { day = TodayDayWindow.step(day, by: delta, today: today) }

    func load(_ repository: VigilRepository) async {
        let target = day
        today = repository.today
        phase = overview == nil ? .loading : phase
        do {
            let overview = try await repository.dayOverview(for: target)
            guard !Task.isCancelled, target == day else { return }
            self.overview = overview
            phase = .loaded
            async let hrvSeries = try? repository.metricSeries(.heartRateVariability, range: .month, endingOn: target)
            async let rhrSeries = try? repository.metricSeries(.restingHeartRate, range: .month, endingOn: target)
            let (h, r) = await (hrvSeries, rhrSeries)
            guard !Task.isCancelled, target == day else { return }
            hrv = h
            restingHeartRate = r
            await loadHistory(repository, endingOn: target, todayScore: overview.recovery?.value)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, target == day else { return }
            phase = .failed
        }
    }

    private func loadHistory(_ repository: VigilRepository, endingOn end: LocalDay, todayScore: Int?) async {
        let days = LocalDay.range(from: end.adding(days: -29), through: end)
        var values: [LocalDay: Int] = [:]
        for summary in repository.summaries.summaries(from: days[0], through: end) {
            if let recovery = summary.recovery { values[summary.day] = recovery.value }
        }
        if let todayScore { values[end] = todayScore }
        history = days.compactMap { d in values[d].map { (d, $0) } }
        for d in days where values[d] == nil {
            if Task.isCancelled || end != day { return }
            if let s = try? await repository.summary(for: d), let recovery = s.recovery {
                values[d] = recovery.value
                history = days.compactMap { d in values[d].map { (d, $0) } }
            }
        }
    }
}

/// Recovery detail for a day (score, factor contributions, 30-day trend, HRV/RHR trends).
struct RecoveryDetailView: View {
    let initialDay: LocalDay
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model: RecoveryDetailModel
    @State private var showsHelp = false

    init(day: LocalDay) {
        initialDay = day
        _model = State(initialValue: RecoveryDetailModel(day: day))
    }

    private var formatter: VigilFormatter { settingsStore.formatter }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.cardGap) {
                switch model.phase {
                case .failed:
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load Recovery",
                                   message: "Something went wrong reading your data.", actionTitle: "Try again") {
                        Task { await model.load(container.repository) }
                    }
                    .vCard()
                case .loading, .loaded:
                    let overview = model.overview ?? TodayPlaceholder.overview(day: model.day)
                    let isPlaceholder = model.overview == nil || model.isStale
                    RecoveryDetailContent(model: model, overview: overview, formatter: formatter)
                        .redacted(reason: isPlaceholder ? .placeholder : [])
                        .allowsHitTesting(!isPlaceholder)
                }
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .vScreenBackground()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TodayDetailTitle(title: String(localized: "Recovery"), subtitle: TodayPresentation.shortDate(model.day))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsHelp = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("How recovery is calculated")
            }
        }
        .task(id: model.day) { await model.load(container.repository) }
        .sheet(isPresented: $showsHelp) { RecoveryExplanationSheet() }
    }
}

private struct RecoveryDetailContent: View {
    let model: RecoveryDetailModel
    let overview: DayOverview
    let formatter: VigilFormatter

    var body: some View {
        VStack(spacing: VSpacing.cardGap) {
            RecoveryHero(model: model, recovery: overview.recovery)
            if let recovery = overview.recovery {
                if recovery.isCalibrating { RecoveryCalibrationCard(recovery: recovery) }
                RecoveryFactorsCard(recovery: recovery, sleepDuration: overview.sleepNight?.asleepDuration, formatter: formatter)
            } else {
                TodayBanner(text: String(localized: "There isn't enough data to score recovery for this day."), systemImage: "heart.slash")
            }
            RecoveryHistoryCard(history: model.history, day: model.day)
            if let hrv = model.hrv, !hrv.points.isEmpty {
                RecoveryTrendCard(series: hrv, day: model.day, formatter: formatter, color: .vRecovery, bandColor: .vRecovery)
            }
            if let rhr = model.restingHeartRate, !rhr.points.isEmpty {
                RecoveryTrendCard(series: rhr, day: model.day, formatter: formatter, color: .vDanger, bandColor: .vDanger)
            }
        }
    }
}

// MARK: - Hero

private struct RecoveryHero: View {
    let model: RecoveryDetailModel
    let recovery: RecoveryScore?

    var body: some View {
        VStack(spacing: VSpacing.xl) {
            HStack(spacing: VSpacing.xl) {
                stepButton("chevron.left", "Previous day", disabled: false) { model.step(by: -1) }
                ring
                stepButton("chevron.right", "Next day", disabled: !model.canStepForward) { model.step(by: 1) }
            }
            if let recovery {
                pill(recovery)
            }
        }
        .padding(.top, VSpacing.xxxl)
        .frame(maxWidth: .infinity)
    }

    private var ring: some View {
        let band = recovery?.band ?? .green
        return ScoreRing(progress: Double(recovery?.value ?? 0) / 100, color: TodayBandStyle.ring(band),
                         track: TodayBandStyle.track(band), diameter: 210) {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(recovery.map { "\($0.value)" } ?? "–")
                        .font(.vCustom(.heading, size: 64, weight: .bold, relativeTo: .largeTitle)).tracking(-0.03 * 64)
                    if recovery != nil { Text("%").font(.vCustom(.body, size: 28, weight: .semibold, relativeTo: .title)) }
                }
                .foregroundStyle(recovery == nil ? Color.vInkTertiary : Color.vInk)
                .minimumScaleFactor(0.6).lineLimit(1)
                Text(recovery == nil ? "no score" : "recovered")
                    .font(.vCustom(.body, size: 15, weight: .semibold, relativeTo: .callout)).foregroundStyle(.vInkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(recovery.map { "Recovery \($0.value) percent, \(TodayPresentation.bandName($0.band))" } ?? "No recovery score"))
    }

    private func stepButton(_ image: String, _ label: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image).font(.system(size: 18, weight: .bold)).foregroundStyle(.vInkSecondary)
                .frame(width: VSize.minTapTarget, height: VSize.minTapTarget).contentShape(.rect)
        }
        .buttonStyle(.vPress)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private func pill(_ recovery: RecoveryScore) -> some View {
        let band = recovery.band
        let color = TodayBandStyle.ring(band)
        let ink: Color = band == .green ? .vRecoveryInk : (band == .yellow ? .vWarningInk : .vDangerInk)
        return HStack(spacing: VSpacing.s) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(TodayPresentation.bandSummary(recovery)).font(.vCustom(.body, size: 14, weight: .bold, relativeTo: .subheadline))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, VSpacing.xl).padding(.vertical, VSpacing.s)
        .background(TodayBandStyle.track(band), in: .capsule)
    }
}

private struct RecoveryCalibrationCard: View {
    let recovery: RecoveryScore

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Label(RecoveryPresentation.calibrationText(recovery) ?? String(localized: "Calibrating"), systemImage: "hourglass")
                .vTextStyle(.bodyStrong).foregroundStyle(.vWarningInk)
            Text("Vigil needs about a week of nights to learn your normal HRV and resting heart rate. Until then this score is a rough estimate and will get more personal each morning.")
                .vTextStyle(.subheadline).foregroundStyle(.vWarningInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VSpacing.cardPadding)
        .background(Color.vWarningTint, in: .rect(cornerRadius: VRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Factors

private struct RecoveryFactorsCard: View {
    let recovery: RecoveryScore
    let sleepDuration: TimeInterval?
    let formatter: VigilFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            VStack(alignment: .leading, spacing: 3) {
                SectionHeader("What drove today's score", style: .card)
                Text("Points added or taken away vs. your baseline").vTextStyle(.footnote).foregroundStyle(.vInkSecondary)
            }
            ForEach(recovery.factors) { factor in
                RecoveryFactorRow(display: RecoveryPresentation.factor(factor, sleepDuration: sleepDuration, formatter: formatter))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }
}

private struct RecoveryFactorRow: View {
    let display: RecoveryPresentation.FactorDisplay

    private var pointsColor: Color {
        display.isPositive ? .vPositive : (display.isNegative ? .vStrainInk : .vInkSecondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: VSpacing.s) {
                Text(display.name).vTextStyle(.bodyStrong).foregroundStyle(.vInk)
                Spacer(minLength: 0)
                Text(display.detail).font(.vCustom(.body, size: 13.5, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.vInkSecondary).multilineTextAlignment(.trailing)
            }
            HStack(spacing: 0) {
                GeometryReader { proxy in
                    let half = (proxy.size.width - 2) / 2
                    ZStack {
                        Rectangle().fill(Color.vInkDisabled).frame(width: 2, height: 18)
                        if display.isNegative {
                            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5)
                                .fill(Color.vStrain)
                                .frame(width: half * display.fraction, height: 10)
                                .offset(x: -(1 + half * display.fraction / 2))
                        }
                        if display.isPositive {
                            UnevenRoundedRectangle(bottomTrailingRadius: 5, topTrailingRadius: 5)
                                .fill(Color.vRecovery)
                                .frame(width: half * display.fraction, height: 10)
                                .offset(x: 1 + half * display.fraction / 2)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                Text(display.points)
                    .font(.vCustom(.body, size: 14, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(pointsColor)
                    .frame(width: 40, alignment: .trailing)
            }
            .frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(display.name))
        .accessibilityValue(Text(display.isAvailable ? "\(display.detail), \(display.points) points" : display.detail))
    }
}

// MARK: - Charts

private struct RecoveryHistoryCard: View {
    let history: [(day: LocalDay, value: Int)]
    let day: LocalDay

    private var average: Int? { RecoveryPresentation.average(history.map(\.value)) }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Last 30 days", style: .card)
                if let average {
                    Text("Avg \(average)%").font(.vCustom(.body, size: 13.5, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
                }
            }
            if history.isEmpty {
                Text("No scores yet").vTextStyle(.callout).foregroundStyle(.vInkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(history, id: \.day) { item in
                    BarMark(x: .value("Day", item.day.startDate(), unit: .day), y: .value("Recovery", item.value))
                        .vBarStyle(Color.vRecoveryBand(RecoveryBand(percent: item.value)), cornerRadius: 3)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [33, 67, 100]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.vChartBaseline)
                        AxisValueLabel().font(.vCaption2).foregroundStyle(Color.vInkSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.vCaption).foregroundStyle(Color.vInkSecondary)
                    }
                }
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recovery over the last 30 days")
                .accessibilityValue(Text("Average \(average ?? 0) percent, latest \(history.last?.value ?? 0) percent"))
            }
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }

    private var legend: some View {
        HStack(spacing: VSpacing.xl) {
            ForEach(RecoveryBand.allCases.reversed(), id: \.self) { band in
                HStack(spacing: VSpacing.xs) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.vRecoveryBand(band)).frame(width: 10, height: 10)
                    Text("\(TodayPresentation.bandName(band)) \(band.range.lowerBound)–\(band.range.upperBound)")
                        .font(.vCustom(.body, size: 12.5, weight: .semibold, relativeTo: .caption)).foregroundStyle(.vInkLabel)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RecoveryTrendCard: View {
    let series: MetricSeries
    let day: LocalDay
    let formatter: VigilFormatter
    let color: Color
    let bandColor: Color

    var body: some View {
        let metric = series.metric
        let points = series.points.map { TodayChartPoint(date: $0.date, value: $0.value) }
        let band = series.baseline.flatMap { $0.isEstablished ? $0.normalRange : nil }
        let latest = points.last.map { formatter.format(metric, $0.value) }
        NavigationLink(value: AppRoute.metric(metric, day)) {
            VStack(alignment: .leading, spacing: VSpacing.l) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.displayName).font(.vCustom(.body, size: 14, weight: .bold, relativeTo: .subheadline)).foregroundStyle(.vInkSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: VSpacing.xs) {
                            Text(latest?.value ?? "–").font(.vCustom(.heading, size: 26, weight: .bold, relativeTo: .title)).foregroundStyle(.vInk)
                            Text(latest?.unit ?? "").vTextStyle(.subheadline).foregroundStyle(.vInkSecondary)
                        }
                    }
                    Spacer(minLength: VSpacing.s)
                    HStack(spacing: VSpacing.xxs) {
                        if let baseline = series.baseline, baseline.isEstablished {
                            Text("Baseline \(formatter.format(metric, baseline.mean).text)")
                        }
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                    }
                    .font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.vInkSecondary)
                }
                TodayLineChart(points: points, band: band, bandColor: bandColor, color: color,
                               yDomain: TodayChartScale.domain(values: points.map(\.value), band: band), height: 110, showsArea: false)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vCard()
            .contentShape(.rect)
        }
        .buttonStyle(.vPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(metric.displayName) trend, last 30 days"))
        .accessibilityValue(Text(latest?.text ?? "No data"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Explanation

private struct RecoveryExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpacing.xxl) {
                    Text("Recovery tells you how ready your body is today, from 0 to 100%. It compares last night with your own normal, not with other people.")
                        .vTextStyle(.body).foregroundStyle(.vInkLabel)
                    section("What goes in", """
                    HRV counts the most, about half. Resting heart rate and your sleep score count about a quarter each. Respiratory rate and wrist temperature only lower the score when they are clearly away from your usual.
                    """)
                    section("Your baseline", """
                    Each signal is compared with your last 30 days. A signal needs at least 7 days of history before it counts, and a signal your watch didn't record is left out, so the score still works with fewer than five signals.
                    """)
                    section("How it becomes a percentage", """
                    If everything sits right at your baseline you land near 58%. Higher HRV, lower resting heart rate and better sleep push you up; the opposite pulls you down. The points under "What drove today's score" add up to the difference from 58.
                    """)
                    section("Colours and advice", """
                    Green is 67 to 100, yellow 34 to 66 and red 0 to 33. Green suggests you push, yellow to maintain and red to take it easy. After an all-out day, or when your recent training load has ramped up too fast, the advice steps down one level. The suggested strain range goes up as recovery goes up.
                    """)
                }
                .padding(VSpacing.screenGutter)
            }
            .vScreenBackground()
            .navigationTitle("How recovery is calculated")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func section(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Text(title).vTextStyle(.headline).foregroundStyle(.vInk).accessibilityAddTraits(.isHeader)
            Text(body).vTextStyle(.body).foregroundStyle(.vInkLabel).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview { RecoveryDetailView(day: .today()).vigilPreview() }
#Preview("Dark") { RecoveryDetailView(day: .today()).vigilPreview().preferredColorScheme(.dark) }
#Preview("Low recovery") { RecoveryDetailView(day: .today()).vigilPreview(.lowRecovery) }
#Preview("New user") { RecoveryDetailView(day: .today()).vigilPreview(.newUser) }
