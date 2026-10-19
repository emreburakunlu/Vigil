import SwiftUI

/// Run detail (route map, splits, pace/HR/elevation charts, zones, running form).
struct RunDetailView: View {
    let workoutID: UUID
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = RunDetailModel()

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ScrollView {
                    TrainSkeletonStack(heights: [120, 110, 90, 260, 200]).padding(VSpacing.screenGutter)
                }
            case .failed:
                ScrollView {
                    TrainErrorCard(title: "Couldn't load this run", message: "The run may have been removed from Health.") {
                        Task { await model.load(id: workoutID, repository: container.repository) }
                    }
                    .padding(VSpacing.screenGutter)
                }
            case .loaded(let detail):
                RunDetailContent(detail: detail, model: model, formatter: settingsStore.formatter, calendar: container.repository.calendar)
            }
        }
        .background(Color.vBackground)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workoutID) { await model.load(id: workoutID, repository: container.repository) }
    }
}

private struct RunDetailContent: View {
    let detail: RunDetail
    @Bindable var model: RunDetailModel
    let formatter: VigilFormatter
    let calendar: Calendar

    private var workout: Workout { detail.workout }
    private var presentation: RunDetailPresentation { model.presentation }
    private var showsMap: Bool { presentation.hasRoute }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.xl) {
                if showsMap { mapHeader }
                summary
                    .padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
                    .padding(.top, showsMap ? 0 : VSpacing.s)
                totals
                TrainStrainCard(strain: detail.strain, note: nil)
                if !detail.splits.isEmpty { splits }
                if hasCharts { charts }
                if detail.zoneDurations.total > 0 { TrainZonesCard(durations: detail.zoneDurations, style: .clock) }
                if hasForm { form }
            }
            .padding(.horizontal, showsMap ? VSpacing.screenGutter : VSpacing.screenGutter)
            .padding(.bottom, VSpacing.huge)
        }
        .modifier(RunMapInsetModifier(extendsUnderBar: showsMap))
        .toolbar {
            if showsMap {
                ToolbarItem(placement: .topBarTrailing) { RunRouteModePicker(mode: $model.colorMode) }
            }
        }
    }

    // MARK: Map

    private var mapHeader: some View {
        ZStack(alignment: .bottom) {
            RunRouteMap(presentation: presentation, mode: model.colorMode, summary: mapLabel)
            RunRouteLegend(mode: model.colorMode)
                .padding(.horizontal, VSpacing.screenGutter)
                .padding(.bottom, VSpacing.xl)
        }
        .frame(height: 400)
        .padding(.horizontal, -VSpacing.screenGutter)
    }

    private var mapLabel: String {
        let distance = workout.distanceMeters.map { formatter.distance(meters: $0).text } ?? ""
        let mode = model.colorMode == .pace ? String(localized: "pace") : String(localized: "heart rate")
        return String(localized: "Route map, \(distance), colored by \(mode)")
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: VSpacing.xs) {
            Text(dateLine).vTextStyle(.subheadline).foregroundStyle(Color.vInkSecondary)
            Text(workout.displayName).vTextStyle(.largeTitle).foregroundStyle(Color.vInk)
                .accessibilityAddTraits(.isHeader)
            let pills = detail.personalBests
            if !pills.isEmpty || !showsMap {
                VStack(alignment: .leading, spacing: VSpacing.s) {
                    ForEach(pills) { best in TrainPersonalBestPill(best: best, formatter: formatter) }
                    if !showsMap { VChip(workout.isIndoor ? "Indoor run · no route" : "No route recorded", systemImage: "location.slash") }
                }
                .padding(.top, VSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLine: String {
        let day = workout.start.formatted(Date.FormatStyle(calendar: calendar).weekday(.wide).month(.abbreviated).day())
        return "\(day) · \(formatter.timeOfDay(workout.start, calendar: calendar)) – \(formatter.timeOfDay(workout.end, calendar: calendar))"
    }

    // MARK: Totals

    private struct Cell: Identifiable {
        var id: String
        var label: LocalizedStringKey
        var value: String
        var unit: String?
    }

    private var cells: [Cell] {
        var result: [Cell] = []
        if let meters = workout.distanceMeters {
            let d = formatter.distance(meters: meters)
            result.append(Cell(id: "distance", label: "Distance", value: d.value, unit: d.unit))
        }
        result.append(Cell(id: "duration", label: "Duration", value: formatter.duration(workout.duration, style: .clock)))
        if let pace = workout.averagePaceSecondsPerKilometer {
            let p = formatter.pace(secondsPerKilometer: pace)
            result.append(Cell(id: "pace", label: "Avg pace", value: p.value, unit: p.unit))
        }
        if let gain = workout.elevationGainMeters {
            let e = formatter.elevation(meters: gain)
            result.append(Cell(id: "elevation", label: "Elevation", value: e.value, unit: e.unit))
        }
        if let energy = workout.activeEnergyKilocalories {
            let e = formatter.energy(kilocalories: energy)
            result.append(Cell(id: "energy", label: "Calories", value: e.value, unit: e.unit))
        }
        if let average = workout.averageHeartRate {
            let avg = formatter.heartRate(bpm: average)
            let value = workout.maxHeartRate.map { avg.value + "/" + formatter.heartRate(bpm: $0).value } ?? avg.value
            result.append(Cell(id: "hr", label: workout.maxHeartRate == nil ? "Avg HR" : "Avg / max HR", value: value, unit: avg.unit))
        }
        return result
    }

    private var totals: some View {
        let rows = stride(from: 0, to: cells.count, by: 3).map { Array(cells[$0..<min($0 + 3, cells.count)]) }
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                if rowIndex > 0 { Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline) }
                HStack(alignment: .top, spacing: VSpacing.s) {
                    ForEach(rows[rowIndex]) { cell in TrainValueCell(label: cell.label, value: cell.value, unit: cell.unit) }
                    ForEach(0..<(3 - rows[rowIndex].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
                .padding(.vertical, VSpacing.xl)
            }
        }
        .padding(.horizontal, VSpacing.cardPadding)
        .padding(.vertical, -VSpacing.xs)
        .frame(maxWidth: .infinity)
        .vCard(padding: 6)
        .accessibilityElement(children: .contain)
    }

    // MARK: Splits

    private var splits: some View {
        let paces = detail.splits.map(\.paceSecondsPerKilometer).filter { $0 > 0 }
        let fastest = paces.min() ?? 0, slowest = paces.max() ?? 0
        let average = paces.isEmpty ? 0 : paces.reduce(0, +) / Double(paces.count)
        return TrainCard(title: "Splits", trailing: String(localized: "per \(formatter.distanceUnit)"), spacing: VSpacing.m) {
            VStack(spacing: 0) {
                HStack(spacing: VSpacing.m) {
                    Text(formatter.distanceUnit).frame(width: 40, alignment: .leading)
                    Text("Pace").frame(maxWidth: .infinity, alignment: .leading)
                    Text("HR").frame(width: 46, alignment: .trailing)
                    Text("Elev").frame(width: 44, alignment: .trailing)
                }
                .font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Color.vInkSecondary)
                .padding(.bottom, VSpacing.s)
                Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline)
                ForEach(detail.splits) { split in
                    splitRow(split, fastest: fastest, slowest: slowest, average: average)
                    Rectangle().fill(Color.vBackground).frame(height: VSize.hairline)
                }
            }
        }
    }

    private func splitRow(_ split: RunSplit, fastest: Double, slowest: Double, average: Double) -> some View {
        let pace = formatter.pace(secondsPerKilometer: split.paceSecondsPerKilometer)
        let label = split.isPartial ? formatter.number(formatter.displayDistance(meters: split.distanceMeters), fractionDigits: 2) : "\(split.index)"
        let fraction = TrainFormatting.splitBarFraction(pace: split.paceSecondsPerKilometer, fastest: fastest, slowest: slowest)
        let isFast = split.paceSecondsPerKilometer <= average
        let elevation = split.elevationChangeMeters.map { formatter.signed(formatter.displayElevation(meters: $0), fractionDigits: 0) } ?? "–"
        let heartRate = split.averageHeartRate.map { formatter.heartRate(bpm: $0).value } ?? "–"
        return HStack(spacing: VSpacing.m) {
            Text(label).font(.vCustom(.body, size: 14, weight: .bold, relativeTo: .subheadline)).foregroundStyle(Color.vInkLabel)
                .frame(width: 40, alignment: .leading)
            HStack(spacing: VSpacing.s) {
                Text(pace.value).font(.vCustom(.body, size: 15, weight: .heavy, relativeTo: .callout)).foregroundStyle(Color.vInk)
                    .frame(minWidth: 38, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.vBackground)
                        Capsule().fill(isFast ? Color.vRun : Color.vRunSoft).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            Text(heartRate).vTextStyle(.subheadline).foregroundStyle(Color.vInk).frame(width: 46, alignment: .trailing)
            Text(elevation).vTextStyle(.subheadline).foregroundStyle(Color.vInkLabel).frame(width: 44, alignment: .trailing)
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Split \(label)")
        .accessibilityValue("\(pace.text), heart rate \(heartRate), elevation \(elevation)")
    }

    // MARK: Charts

    private var hasCharts: Bool {
        presentation.pace.count > 1 || presentation.heartRate.count > 1 || presentation.elevation.count > 1
    }

    private var xTicks: [(value: Double, label: String)] {
        if presentation.xIsDistance {
            let ticks = TrainSeries.distanceTicks(maxMeters: presentation.xMax, formatter: formatter)
            return ticks.enumerated().map { index, meters in
                let number = formatter.number(formatter.displayDistance(meters: meters), fractionDigits: 0)
                return (meters, index == ticks.count - 1 ? "\(number) \(formatter.distanceUnit)" : number)
            }
        }
        let minutes = max(presentation.xMax / 60, 1)
        let step = [5.0, 10, 15, 30, 60].first { minutes / $0 <= 4 } ?? 60
        return stride(from: 0, through: minutes, by: step).map { ($0 * 60, formatter.duration($0 * 60, style: .clock)) }
    }

    private var charts: some View {
        let ticks = xTicks
        let lastIsElevation = presentation.elevation.count > 1
        let lastIsHR = !lastIsElevation && presentation.heartRate.count > 1
        return VStack(alignment: .leading, spacing: VSpacing.cardPadding) {
            if presentation.pace.count > 1 {
                chartBlock("Pace", summary: paceSummary) {
                    TrainSeriesChart(points: presentation.pace, color: .vRun, invertY: true, xMax: presentation.xMax,
                                     xTicks: (!lastIsElevation && !lastIsHR) ? ticks : nil)
                }
            }
            if presentation.heartRate.count > 1 {
                chartBlock("Heart rate", summary: hrSummary) {
                    TrainSeriesChart(points: presentation.heartRate, color: .vDanger, xMax: presentation.xMax,
                                     xTicks: lastIsHR ? ticks : nil)
                }
            }
            if presentation.elevation.count > 1 {
                chartBlock("Elevation", summary: elevationSummary) {
                    TrainSeriesChart(points: presentation.elevation, color: .vInkSecondary, xMax: presentation.xMax, height: 64, xTicks: ticks)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }

    private func chartBlock<Chart: View>(_ title: LocalizedStringKey, summary: String, @ViewBuilder chart: () -> Chart) -> some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
                Spacer(minLength: VSpacing.s)
                Text(summary).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
            }
            chart()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(summary)
        }
    }

    private var paceSummary: String {
        var parts: [String] = []
        if let average = workout.averagePaceSecondsPerKilometer {
            parts.append(String(localized: "avg \(formatter.pace(secondsPerKilometer: average).value)"))
        }
        if let best = presentation.bestPace {
            let value = formatter.pace(secondsPerKilometer: best)
            parts.append(String(localized: "best \(value.value) \(value.unit)"))
        }
        return parts.joined(separator: " · ")
    }

    private var hrSummary: String {
        guard let average = workout.averageHeartRate else { return "" }
        var text = String(localized: "avg \(formatter.heartRate(bpm: average).value)")
        if let max = workout.maxHeartRate { text += " · " + String(localized: "max \(formatter.heartRate(bpm: max).text)") }
        return text
    }

    private var elevationSummary: String {
        guard let gain = workout.elevationGainMeters else { return "" }
        var text = formatter.elevationChange(meters: gain).text
        if let loss = workout.elevationLossMeters { text += " · " + formatter.elevationChange(meters: -abs(loss)).text }
        return text
    }

    // MARK: Running form

    private var formTiles: [Cell] {
        let form = detail.details.form
        var result: [Cell] = []
        if let v = form.cadence { let f = formatter.cadence(stepsPerMinute: v); result.append(Cell(id: "cadence", label: "Cadence", value: f.value, unit: f.unit)) }
        if let v = form.strideLength { let f = formatter.strideLength(meters: v); result.append(Cell(id: "stride", label: "Stride length", value: f.value, unit: f.unit)) }
        if let v = form.groundContactTime { let f = formatter.groundContactTime(milliseconds: v); result.append(Cell(id: "gct", label: "Ground contact", value: f.value, unit: f.unit)) }
        if let v = form.verticalOscillation { let f = formatter.verticalOscillation(centimeters: v); result.append(Cell(id: "vo", label: "Vertical oscillation", value: f.value, unit: f.unit)) }
        if let v = form.power { let f = formatter.power(watts: v); result.append(Cell(id: "power", label: "Running power", value: f.value, unit: f.unit)) }
        return result
    }

    private var hasForm: Bool { !formTiles.isEmpty }

    private var form: some View {
        let device = workout.heartRateSource?.deviceName ?? workout.source.deviceName ?? workout.source.name
        return TrainCard(title: "Running form", spacing: VSpacing.l) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: VSpacing.m), GridItem(.flexible())], spacing: VSpacing.m) {
                ForEach(formTiles) { tile in
                    TrainTile(label: tile.label, value: tile.value, unit: tile.unit)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Source").font(.vCustom(.body, size: 12.5, weight: .semibold, relativeTo: .caption)).foregroundStyle(Color.vInkSecondary)
                    Text(device).vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VSpacing.cardPaddingCompact)
                .padding(.vertical, VSpacing.l)
                .background(Color.vCardRaised, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Lets the map header run under the transparent navigation bar.
private struct RunMapInsetModifier: ViewModifier {
    let extendsUnderBar: Bool

    func body(content: Content) -> some View {
        if extendsUnderBar {
            content
                .ignoresSafeArea(.container, edges: .top)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}

/// "Personal best · Fastest 5K 26:02" pill.
struct TrainPersonalBestPill: View {
    let best: PersonalBest
    let formatter: VigilFormatter

    private var text: String {
        if let duration = best.duration {
            return String(localized: "Personal best · Fastest \(best.category.displayName) \(formatter.duration(duration, style: .clock))")
        }
        return String(localized: "Personal best · Longest run \(formatter.distance(meters: best.distanceMeters, fractionDigits: 1).text)")
    }

    var body: some View {
        HStack(spacing: VSpacing.xs) {
            Image(systemName: "trophy.fill").foregroundStyle(Color.vWarning).accessibilityHidden(true)
            Text(text)
        }
        .font(.vCustom(.body, size: 13.5, weight: .bold, relativeTo: .footnote))
        .foregroundStyle(Color.vInkOnInverse)
        .padding(.horizontal, VSpacing.l)
        .frame(minHeight: 34)
        .background(Color.vInverseFill, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RunDetailView(workoutID: UUID()).vigilPreview()
}
