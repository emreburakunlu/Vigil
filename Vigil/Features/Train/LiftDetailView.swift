import Charts
import SwiftUI

/// Heart-rate series for a lift, downsampled off the main actor.
struct LiftDetailPresentation: Sendable {
    var points: [TrainChartPoint] = []
    var domain: ClosedRange<Double> = 90...185

    static func make(from detail: LiftDetail) -> LiftDetailPresentation {
        let start = detail.workout.start
        let points = TrainSeries.series(from: detail.heartRate, maxPoints: 240, x: { $0.timeIntervalSince(start) }) { $0 > 20 && $0 < 260 }
        guard let low = points.map(\.y).min(), let high = points.map(\.y).max() else { return LiftDetailPresentation() }
        let zoneFloor = Double(detail.zones.zones.first?.lowerBound ?? 90)
        let zoneCeiling = Double(detail.zones.maxHeartRate)
        let lo = max(min(low - 5, zoneFloor), 30)
        let hi = max(high + 5, min(zoneCeiling, high + 25))
        return LiftDetailPresentation(points: points, domain: lo...hi)
    }

    @concurrent
    static func build(from detail: LiftDetail) async -> LiftDetailPresentation { make(from: detail) }
}

enum LiftDetailLoadState {
    case loading
    case loaded(LiftDetail)
    case failed
}

@MainActor
@Observable
final class LiftDetailModel {
    private(set) var state: LiftDetailLoadState = .loading
    private(set) var presentation = LiftDetailPresentation()

    func load(id: UUID, repository: VigilRepository) async {
        state = .loading
        do {
            let detail = try await repository.liftDetail(id: id)
            presentation = await LiftDetailPresentation.build(from: detail)
            state = .loaded(detail)
        } catch {
            state = .failed
        }
    }
}

/// Lift detail (duration, calories, HR chart, zones, strain, source app). Sets and reps are not available from Health.
struct LiftDetailView: View {
    let workoutID: UUID
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @State private var model = LiftDetailModel()

    var body: some View {
        ScrollView {
            switch model.state {
            case .loading:
                TrainSkeletonStack(heights: [90, 140, 220, 200]).padding(VSpacing.screenGutter)
            case .failed:
                TrainErrorCard(title: "Couldn't load this workout", message: "The workout may have been removed from Health.") {
                    Task { await model.load(id: workoutID, repository: container.repository) }
                }
                .padding(VSpacing.screenGutter)
            case .loaded(let detail):
                LiftDetailContent(detail: detail, presentation: model.presentation, formatter: settingsStore.formatter,
                                  calendar: container.repository.calendar)
            }
        }
        .background(Color.vBackground)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workoutID) { await model.load(id: workoutID, repository: container.repository) }
    }
}

private struct LiftDetailContent: View {
    let detail: LiftDetail
    let presentation: LiftDetailPresentation
    let formatter: VigilFormatter
    let calendar: Calendar

    private var workout: Workout { detail.workout }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            summary.padding(.horizontal, VSpacing.headerGutter - VSpacing.screenGutter)
            totals
            if presentation.points.count > 1 { heartRateCard }
            if detail.zoneDurations.total > 0 { TrainZonesCard(durations: detail.zoneDurations, style: .hoursMinutes) }
            TrainStrainCard(strain: detail.strain, note: "based on heart rate, not weight lifted")
            sourceCard
        }
        .padding(.horizontal, VSpacing.screenGutter)
        .padding(.bottom, VSpacing.huge)
    }

    private var summary: some View {
        let day = workout.start.formatted(Date.FormatStyle(calendar: calendar).weekday(.wide).month(.abbreviated).day())
        let line = "\(day) · \(formatter.timeOfDay(workout.start, calendar: calendar)) – \(formatter.timeOfDay(workout.end, calendar: calendar))"
        return VStack(alignment: .leading, spacing: VSpacing.xs) {
            Text(line).vTextStyle(.subheadline).foregroundStyle(Color.vInkSecondary)
            Text(workout.displayName).vTextStyle(.largeTitle).foregroundStyle(Color.vInk).accessibilityAddTraits(.isHeader)
            HStack(spacing: VSpacing.s) {
                HStack(spacing: VSpacing.xs) {
                    Circle().fill(Color.vLift).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(workout.activityName)
                }
                .modifier(LiftPill())
                Text("via \(workout.source.name)").modifier(LiftPill())
            }
            .padding(.top, VSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totals: some View {
        let active = workout.activeEnergyKilocalories.map { formatter.energy(kilocalories: $0) }
        let total = workout.totalEnergyKilocalories.map { formatter.energy(kilocalories: $0) }
        let average = workout.averageHeartRate.map { formatter.heartRate(bpm: $0) }
        let maximum = workout.maxHeartRate.map { formatter.heartRate(bpm: $0) }
        return VStack(spacing: VSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration").vTextStyle(.subheadline).foregroundStyle(Color.vInkSecondary)
                Spacer()
                Text(formatter.duration(workout.duration, style: .clock)).vTextStyle(.title).foregroundStyle(Color.vInk)
            }
            .padding(.horizontal, VSpacing.cardPadding)
            .padding(.vertical, VSpacing.xxl)
            .frame(maxWidth: .infinity)
            .vCard(padding: 0, radius: 22)
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: VSpacing.m), GridItem(.flexible())], spacing: VSpacing.m) {
                if let active { statCard("Active calories", active) }
                if let total { statCard("Total calories", total) }
                if let average { statCard("Avg heart rate", average) }
                if let maximum { statCard("Max heart rate", maximum) }
            }
        }
    }

    private func statCard(_ label: LocalizedStringKey, _ value: FormattedValue) -> some View {
        TrainValueCell(label: label, value: value.value, unit: value.unit)
            .vCard(padding: VSpacing.cardPaddingCompact, radius: 20)
    }

    private var heartRateCard: some View {
        TrainCard(title: "Heart rate", spacing: VSpacing.l) {
            LiftHeartRateChart(points: presentation.points, domain: presentation.domain, zones: detail.zones, start: workout.start)
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Heart rate during session")
                .accessibilityValue(hrSummary)
        }
    }

    private var hrSummary: String {
        [workout.averageHeartRate.map { String(localized: "average \(formatter.heartRate(bpm: $0).text)") },
         workout.maxHeartRate.map { String(localized: "maximum \(formatter.heartRate(bpm: $0).text)") }]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private var sourceCard: some View {
        let heartRateFrom = workout.heartRateSource.map { $0.deviceName ?? $0.name }
        return VStack(spacing: 0) {
            sourceRow("Recorded by", workout.source.name)
            if let heartRateFrom {
                Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline)
                sourceRow("Heart rate from", heartRateFrom)
            }
            if !workout.source.isApple {
                Rectangle().fill(Color.vSeparator).frame(height: VSize.hairline)
                sourceRow("Sets, reps, weights", String(localized: "See \(workout.source.name)"), secondary: true)
            }
        }
        .padding(.horizontal, VSpacing.cardPadding)
        .vCard(padding: 0)
    }

    private func sourceRow(_ title: LocalizedStringKey, _ value: String, secondary: Bool = false) -> some View {
        HStack {
            Text(title).vTextStyle(.callout).fontWeight(.semibold).foregroundStyle(Color.vInk)
            Spacer(minLength: VSpacing.l)
            Text(value).vTextStyle(.bodyStrong).foregroundStyle(secondary ? Color.vInkSecondary : Color.vInk)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

private struct LiftPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
            .foregroundStyle(Color.vInk)
            .padding(.horizontal, VSpacing.l)
            .frame(minHeight: 30)
            .background(Color.vCard, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.vHairline, lineWidth: VSize.hairline))
    }
}

/// Session heart rate over time on top of tinted zone bands (Z1 at the bottom, labelled on the right).
private struct LiftHeartRateChart: View {
    let points: [TrainChartPoint]
    let domain: ClosedRange<Double>
    let zones: HeartRateZones
    let start: Date

    private var bands: [(zone: Int, low: Double, high: Double)] {
        zones.zones.enumerated().compactMap { index, zone in
            let low = max(Double(zone.lowerBound), domain.lowerBound)
            let upper = index + 1 < zones.zones.count ? Double(zones.zones[index + 1].lowerBound) : domain.upperBound
            let high = min(max(upper, low), domain.upperBound)
            // Zone 1 extends down to the bottom of the chart.
            let bottom = index == 0 ? domain.lowerBound : low
            return high > bottom ? (zone.number, bottom, high) : nil
        }
    }

    var body: some View {
        let bands = bands
        Chart {
            ForEach(bands, id: \.zone) { band in
                RectangleMark(yStart: .value("Zone low", band.low), yEnd: .value("Zone high", band.high))
                    .foregroundStyle(Color.vZone(band.zone).opacity(0.14))
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.x), y: .value("Heart rate", point.y))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.vInk)
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: 0...max(points.last?.x ?? 1, 1))
        .chartYAxis {
            AxisMarks(position: .trailing, values: bands.map { ($0.low + $0.high) / 2 }) { value in
                AxisValueLabel {
                    if let bpm = value.as(Double.self), let band = bands.first(where: { ($0.low + $0.high) / 2 == bpm }) {
                        Text("Z\(band.zone)").font(.vCaption2).fontWeight(.bold).foregroundStyle(Color.vInkLabel)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(start.addingTimeInterval(seconds).formatted(.dateTime.hour().minute()))
                            .font(.vCaption).foregroundStyle(Color.vInkSecondary)
                    }
                }
            }
        }
    }
}

#Preview {
    LiftDetailView(workoutID: UUID()).vigilPreview()
}
