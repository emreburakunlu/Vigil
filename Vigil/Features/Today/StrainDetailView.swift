import Charts
import SwiftUI

/// State of the Strain detail screen.
@MainActor
@Observable
final class StrainDetailModel {
    enum Phase: Equatable { case loading, loaded, failed }

    private(set) var phase: Phase = .loading
    private(set) var overview: DayOverview?
    private(set) var zones: HeartRateZones?
    private(set) var load: TrainingLoad?
    private(set) var today: LocalDay
    var day: LocalDay

    init(day: LocalDay, today: LocalDay = .today()) {
        self.day = day
        self.today = today
    }

    var isStale: Bool { overview?.day != day }

    /// Follows `AppContainer.currentDay`: a screen showing the old today moves to the new one.
    func rollOver(to newToday: LocalDay) {
        guard newToday != today else { return }
        if day == today { day = newToday }
        today = newToday
    }

    func load(_ repository: VigilRepository) async {
        let target = day
        if overview == nil { phase = .loading }
        do {
            let overview = try await repository.dayOverview(for: target)
            let load = try? await repository.trainingLoad(endingOn: target)
            guard !Task.isCancelled, target == day else { return }
            self.overview = overview
            self.zones = repository.heartRateZones()
            self.load = load
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, target == day else { return }
            phase = .failed
        }
    }
}

/// Strain detail for a day (zones, per-workout strain, training load).
struct StrainDetailView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model: StrainDetailModel
    @State private var isPickingDate = false

    init(day: LocalDay) {
        _model = State(initialValue: StrainDetailModel(day: day))
    }

    private var formatter: VigilFormatter { settingsStore.formatter }

    private struct LoadKey: Hashable { var day: LocalDay; var version: Int; var current: LocalDay }

    var body: some View {
        ScrollView {
            VStack(spacing: VSpacing.cardGap) {
                switch model.phase {
                case .failed:
                    VErrorCard(title: "Couldn't load Strain", message: "Something went wrong reading your data.") {
                        Task { await model.load(container.repository) }
                    }
                case .loading, .loaded:
                    let overview = model.overview ?? TodayPlaceholder.overview(day: model.day)
                    let isPlaceholder = model.overview == nil || model.isStale
                    StrainDetailContent(overview: overview, zones: model.zones, load: model.load, formatter: formatter)
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
                TodayDetailTitle(title: String(localized: "Strain"), subtitle: TodayPresentation.shortDate(model.day))
            }
            ToolbarItem(placement: .primaryAction) {
                CircleIconButton(systemImage: "calendar", label: "Choose a date") { isPickingDate = true }
            }
        }
        .task(id: LoadKey(day: model.day, version: container.dataVersion, current: container.currentDay)) {
            model.rollOver(to: container.currentDay)
            await model.load(container.repository)
        }
        .sheet(isPresented: $isPickingDate) {
            TodayDatePickerSheet(selection: model.day, today: model.today) { model.day = min($0, model.today) }
        }
    }
}

private struct StrainDetailContent: View {
    let overview: DayOverview
    let zones: HeartRateZones?
    let load: TrainingLoad?
    let formatter: VigilFormatter

    var body: some View {
        VStack(spacing: VSpacing.cardGap) {
            StrainGaugeSection(strain: overview.strain, recovery: overview.recovery)
            if let strain = overview.strain {
                if let zones, strain.zoneDurations.total > 0 {
                    StrainZonesCard(durations: strain.zoneDurations, zones: zones, workoutCount: strain.workouts.count, formatter: formatter)
                }
                StrainWorkoutsCard(overview: overview, strain: strain, formatter: formatter)
            } else {
                TodayBanner(text: String(localized: "No strain was recorded for this day."), systemImage: "flame")
            }
            if let load { StrainLoadCard(load: load, formatter: formatter) }
        }
    }
}

// MARK: - Gauge

private struct StrainGaugeSection: View {
    let strain: DailyStrain?
    let recovery: RecoveryScore?
    private let sweep = 0.75

    var body: some View {
        VStack(spacing: VSpacing.xxs) {
            ZStack {
                Circle().trim(from: 0, to: sweep)
                    .stroke(Color.vStrainTint, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(30)
                Circle().trim(from: 0, to: sweep * StrainPresentation.gaugeFraction(strain?.value ?? 0))
                    .stroke(Color.vStrain, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(30)
                if let range = recovery?.suggestedStrain {
                    Circle().trim(from: sweep * StrainPresentation.gaugeFraction(range.lowerBound),
                                  to: sweep * StrainPresentation.gaugeFraction(range.upperBound))
                        .stroke(Color.vInk, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .padding(12)
                }
                VStack(spacing: 2) {
                    Text(strain.map { "\($0.value)" } ?? "–")
                        .font(.vCustom(.heading, size: 66, weight: .bold, relativeTo: .largeTitle)).tracking(-0.03 * 66)
                        .foregroundStyle(strain == nil ? Color.vInkTertiary : Color.vInk)
                    Text(strain.map { TodayPresentation.strainLevelName($0.level) } ?? String(localized: "No data"))
                        .font(.vCustom(.body, size: 15, weight: .bold, relativeTo: .callout))
                        .foregroundStyle(strain == nil ? Color.vInkSecondary : Color.vStrainInk)
                }
                .offset(y: -6)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: 240, height: 240)
            .frame(height: 210, alignment: .top)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(strain.map { "Strain \($0.value), \(TodayPresentation.strainLevelName($0.level))" } ?? "No strain"))
            if let text = StrainPresentation.suggestedText(recovery) {
                HStack(spacing: VSpacing.s) {
                    Capsule().fill(Color.vInk).frame(width: 18, height: 4).accessibilityHidden(true)
                    Text(text).font(.vCustom(.body, size: 14, weight: .semibold, relativeTo: .subheadline)).foregroundStyle(.vInkLabel)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Zones

private struct StrainZonesCard: View {
    let durations: ZoneDurations
    let zones: HeartRateZones
    let workoutCount: Int
    let formatter: VigilFormatter
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let rows = StrainPresentation.zoneRows(durations: durations, zones: zones, formatter: formatter)
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Heart rate zones", style: .card)
                Text(StrainPresentation.zoneSummary(durations: durations, workoutCount: workoutCount, formatter: formatter))
                    .font(.vCustom(.body, size: 13.5, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { proxy in
                let shown = rows.filter { $0.fraction > 0 }
                let usable = proxy.size.width - 2 * Double(max(shown.count - 1, 0))
                HStack(spacing: 2) {
                    ForEach(shown) { row in
                        Rectangle().fill(Color.vZone(row.number)).frame(width: usable * row.fraction)
                    }
                }
            }
            .frame(height: VSize.zoneBarHeight)
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
            ForEach(rows) { row in
                zoneRow(row)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Zone \(row.number), \(row.name)"))
                    .accessibilityValue(Text("\(row.duration), \(row.range)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }

    private func zoneChip(_ row: StrainPresentation.ZoneRow) -> some View {
        Text("Z\(row.number)")
            .font(.vCustom(.body, size: 13, weight: .heavy, relativeTo: .footnote))
            .foregroundStyle(chipInk(row.number))
            .fixedSize()
            .frame(minWidth: 34, minHeight: 26)
            .padding(.horizontal, VSpacing.xxs)
            .background(Color.vZone(row.number), in: .rect(cornerRadius: 8, style: .continuous))
    }

    private func zoneBar(_ row: StrainPresentation.ZoneRow) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.vFill)
                Capsule().fill(Color.vZone(row.number)).frame(width: proxy.size.width * row.relativeFraction)
            }
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private func zoneRow(_ row: StrainPresentation.ZoneRow) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: VSpacing.xs) {
                HStack(spacing: VSpacing.m) {
                    zoneChip(row)
                    Text(row.name).font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote)).foregroundStyle(.vInk)
                    Spacer(minLength: VSpacing.xs)
                    Text(row.duration).font(.vCustom(.body, size: 15, weight: .heavy, relativeTo: .callout)).foregroundStyle(.vInk)
                }
                Text(row.range).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
                zoneBar(row)
            }
        } else {
            HStack(spacing: VSpacing.m) {
                zoneChip(row)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.name).font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote)).foregroundStyle(.vInk)
                        Spacer(minLength: VSpacing.xs)
                        Text(row.range).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(.vInkSecondary)
                    }
                    zoneBar(row)
                }
                Text(row.duration)
                    .font(.vCustom(.body, size: 15, weight: .heavy, relativeTo: .callout)).foregroundStyle(.vInk)
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }

    private func chipInk(_ zone: Int) -> Color {
        if scheme == .dark { return .vBackground }
        return zone == 2 ? .vInkOnAccent : .vInk
    }
}

// MARK: - Workouts

private struct StrainWorkoutsCard: View {
    let overview: DayOverview
    let strain: DailyStrain
    let formatter: VigilFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xs) {
            SectionHeader("Strain per workout", style: .card).padding(.bottom, VSpacing.xs)
            ForEach(overview.workouts) { item in
                switch item.workout.kind {
                case .run:
                    NavigationLink(value: AppRoute.runDetail(item.id)) { row(item) }.buttonStyle(.vPress)
                case .strength:
                    NavigationLink(value: AppRoute.liftDetail(item.id)) { row(item) }.buttonStyle(.vPress)
                case .other:
                    row(item)
                }
            }
            StrainWorkoutRow(icon: "figure.walk", iconColor: .vInkLabel, iconBackground: .vFill, title: String(localized: "Everyday movement"),
                             subtitle: nil, value: strain.everydayMovement, barColor: .vInkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }

    private func row(_ item: WorkoutSummary) -> some View {
        let workout = item.workout
        let icon: (String, Color, Color) = switch workout.kind {
        case .run: ("figure.run", .vRun, .vRunTint)
        case .strength: ("dumbbell.fill", .vStrainInk, .vLiftTint)
        case .other: ("figure.mixed.cardio", .vInkLabel, .vFill)
        }
        return StrainWorkoutRow(icon: icon.0, iconColor: icon.1, iconBackground: icon.2, title: workout.displayName,
                                subtitle: formatter.timeOfDay(workout.start), value: item.strain?.value, barColor: .vStrain)
    }
}

private struct StrainWorkoutRow: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let subtitle: String?
    let value: Int?
    let barColor: Color

    var body: some View {
        HStack(spacing: VSpacing.l) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(iconColor)
                .frame(width: 40, height: 40).background(iconBackground, in: .rect(cornerRadius: VRadius.chip, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(Text(title).font(.vCustom(.body, size: 15, weight: .bold, relativeTo: .callout)).foregroundStyle(.vInk))\(Text(subtitle.map { " · \($0)" } ?? "").font(.vCustom(.body, size: 15, weight: .semibold, relativeTo: .callout)).foregroundStyle(.vInkSecondary))")
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.vFill)
                        Capsule().fill(barColor).frame(width: proxy.size.width * Double(value ?? 0) / 100)
                    }
                }
                .frame(height: 6)
            }
            Text(value.map { "\($0)" } ?? "–")
                .font(.vCustom(.heading, size: 22, weight: .bold, relativeTo: .title3)).foregroundStyle(.vInk)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .frame(minHeight: 56)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value.map { "strain \($0)" } ?? "no strain"))
    }
}

// MARK: - Training load

private struct StrainLoadCard: View {
    let load: TrainingLoad
    let formatter: VigilFormatter
    @Environment(\.dynamicTypeSize) private var typeSize

    private var riskColor: Color {
        switch load.risk {
        case .productive: .vPositive
        case .detraining: .vInkSecondary
        case .caution: .vWarningInk
        case .high: .vDangerInk
        }
    }

    var body: some View {
        let history = load.history
        let top = history.flatMap { [$0.acute, $0.chronic * 1.3] }
        VStack(alignment: .leading, spacing: VSpacing.l) {
            let headerLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: VSpacing.m))
                : AnyLayout(HStackLayout(alignment: .top, spacing: VSpacing.m))
            headerLayout {
                VStack(alignment: .leading, spacing: 3) {
                    SectionHeader("Training load", style: .card).lineLimit(1).minimumScaleFactor(0.7)
                    Text("7-day vs. 28-day, last 8 weeks").vTextStyle(.footnote).foregroundStyle(.vInkSecondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(load.ratio.map { formatter.number($0, fractionDigits: 2) } ?? "–")
                        .font(.vCustom(.heading, size: 24, weight: .bold, relativeTo: .title2)).foregroundStyle(.vInk)
                    Text(StrainPresentation.riskName(load.risk))
                        .font(.vCustom(.body, size: 12.5, weight: .bold, relativeTo: .caption)).foregroundStyle(riskColor)
                }
            }
            if history.count > 1 {
                Chart {
                    ForEach(history) { point in
                        AreaMark(x: .value("Day", point.day.startDate()), yStart: .value("Low", point.chronic * 0.8),
                                 yEnd: .value("High", point.chronic * 1.3), series: .value("Series", "band"))
                            .foregroundStyle(Color.vRecovery.opacity(0.16))
                        LineMark(x: .value("Day", point.day.startDate()), y: .value("Load", point.chronic), series: .value("Series", "chronic"))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                            .foregroundStyle(Color.vInkTertiary)
                        LineMark(x: .value("Day", point.day.startDate()), y: .value("Load", point.acute), series: .value("Series", "acute"))
                            .vLineStyle(.vStrain, width: 2.8)
                    }
                    if let last = history.last {
                        VEndDot(x: .value("Day", last.day.startDate()), y: .value("Load", last.acute), color: .vStrain)
                    }
                }
                .vChartAxes(yCount: 3, xValues: .automatic(desiredCount: 4), xFormat: .dateTime.month(.abbreviated).day())
                .chartYScale(domain: 0...((top.max() ?? 1) * 1.1))
                .frame(height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Training load, 7-day against 28-day")
                .accessibilityValue(Text("Ratio \(load.ratio.map { formatter.number($0, fractionDigits: 2) } ?? "unknown"), \(StrainPresentation.riskName(load.risk))"))
            } else {
                Text("Not enough training history yet.").vTextStyle(.callout).foregroundStyle(.vInkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VSpacing.xxl) { items }
            VStack(alignment: .leading, spacing: VSpacing.s) { items }
        }
        .font(.vCustom(.body, size: 12.5, weight: .semibold, relativeTo: .caption))
        .foregroundStyle(.vInkLabel)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var items: some View {
        HStack(spacing: VSpacing.xs) { Capsule().fill(Color.vStrain).frame(width: 16, height: 3); Text("7-day load") }
        HStack(spacing: VSpacing.xs) {
            Rectangle().stroke(Color.vInkTertiary, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: 16, height: 2)
            Text("28-day load")
        }
        HStack(spacing: VSpacing.xs) {
            RoundedRectangle(cornerRadius: 3).fill(Color.vRecovery.opacity(0.16)).frame(width: 12, height: 12)
            Text("Productive range (0.8–1.3×)")
        }
    }
}

#Preview { StrainDetailView(day: .today()).vigilPreview() }
#Preview("Dark") { StrainDetailView(day: .today()).vigilPreview().preferredColorScheme(.dark) }
#Preview("New user") { StrainDetailView(day: .today()).vigilPreview(.newUser) }
