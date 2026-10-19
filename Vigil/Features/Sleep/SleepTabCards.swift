import SwiftUI

// MARK: - Debt

/// Bars for the last 7 nights against the target, with the shortfall outlined above each bar.
struct SleepDebtCard: View {
    let debt: SleepDebt
    let formatter: VigilFormatter
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var plotHeight: CGFloat = 110

    private var floorSeconds: TimeInterval { max(0, debt.target - 3 * 3600) }

    private func fraction(_ asleep: TimeInterval) -> CGFloat {
        let span = debt.target - floorSeconds
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (asleep - floorSeconds) / span)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep debt").vTextStyle(.headline).foregroundStyle(Color.vNightInk).accessibilityAddTraits(.isHeader)
                    Text("Shortfall vs. \(SleepFormat.targetText(debt.target, formatter: formatter)), last 7 nights")
                        .vTextStyle(.footnote).foregroundStyle(Color.vNightInkSecondary)
                }
                Spacer(minLength: VSpacing.s)
                Text(formatter.duration(debt.total))
                    .font(.vCustom(.heading, size: 28, weight: .bold, relativeTo: .title))
                    .foregroundStyle(Color.vNightNegative)
            }
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color.vNightInkLabel.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(height: 0)
                    .padding(.top, 1)
                Text(SleepFormat.targetText(debt.target, formatter: formatter))
                    .vTextStyle(.caption2).fontWeight(.bold)
                    .foregroundStyle(Color.vNightInkSecondary)
                    .padding(.leading, VSpacing.xxs)
                    .background(Color.vNightCard)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: -8)
                HStack(alignment: .bottom, spacing: VSpacing.m) {
                    ForEach(debt.nights) { night in column(night) }
                }
                .padding(.top, 2)
            }
            .frame(height: plotHeight)
            HStack(spacing: VSpacing.m) {
                ForEach(debt.nights) { night in
                    Text(weekdayLetter(night.day))
                        .vTextStyle(.caption).fontWeight(.bold)
                        .foregroundStyle(Color.vNightInkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vNightCard(padding: VSpacing.xxl, radius: VRadius.cardLarge)
        .accessibilityElement(children: .contain)
    }

    private func weekdayLetter(_ day: LocalDay) -> String {
        let index = calendar.component(.weekday, from: day.startDate(in: calendar)) - 1
        return calendar.veryShortWeekdaySymbols[index]
    }

    private func column(_ night: SleepDebtNight) -> some View {
        let barHeight = night.asleep.map { fraction($0) * plotHeight } ?? 0
        let gap = max(0, plotHeight - barHeight)
        let met = (night.asleep ?? 0) >= debt.target
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            if !met {
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                    .strokeBorder(Color.vStageAwake, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(height: gap)
            }
            if barHeight > 0 {
                UnevenRoundedRectangle(topLeadingRadius: met ? 6 : 0, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: met ? 6 : 0)
                    .fill(met ? Color.vSleep : Color.vStageCore)
                    .frame(height: barHeight)
            }
        }
        .frame(height: plotHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(label(night))
    }

    private func label(_ night: SleepDebtNight) -> String {
        let day = SleepFormat.spokenDate(night.day, calendar: calendar)
        guard let asleep = night.asleep else { return String(localized: "\(day), no sleep recorded") }
        let slept = formatter.duration(asleep)
        return night.shortfall > 0
            ? String(localized: "\(day), \(slept) asleep, \(formatter.duration(night.shortfall)) short")
            : String(localized: "\(day), \(slept) asleep, target met")
    }
}

// MARK: - Trends

struct SleepTrendsCard: View {
    @Bindable var model: SleepModel

    @ScaledMetric(relativeTo: .body) private var plotHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            HStack {
                Text("Trends").vTextStyle(.headline).foregroundStyle(Color.vNightInk).accessibilityAddTraits(.isHeader)
                Spacer(minLength: VSpacing.s)
                rangePicker
            }
            HStack(spacing: VSpacing.xs) {
                ForEach(SleepTrendMetric.allCases, id: \.self) { metric in metricButton(metric) }
            }
            if let chart = model.chart {
                HStack(alignment: .firstTextBaseline, spacing: VSpacing.s) {
                    Text(chart.headline).font(.vCustom(.heading, size: 26, weight: .bold, relativeTo: .title)).foregroundStyle(Color.vNightInk)
                    Text(chart.subtitle).vTextStyle(.footnote).foregroundStyle(Color.vNightInkSecondary)
                }
                SleepBarsCanvas(bars: chart.bars)
                    .frame(height: plotHeight)
                    .accessibilityElement()
                    .accessibilityLabel(chart.accessibility)
                HStack {
                    ForEach(Array(chart.ticks.enumerated()), id: \.offset) { index, tick in
                        Text(tick)
                        if index < chart.ticks.count - 1 { Spacer() }
                    }
                }
                .vTextStyle(.caption)
                .foregroundStyle(Color.vNightInkSecondary)
                .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: VRadius.tile, style: .continuous).fill(Color.vNightFill.opacity(0.5)).frame(height: plotHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vNightCard(padding: VSpacing.xxl, radius: VRadius.cardLarge)
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(SleepTrendRange.allCases, id: \.self) { range in
                let selected = range == model.range
                Button { model.range = range } label: {
                    Text(range.title)
                        .vTextStyle(.footnote).fontWeight(.bold)
                        .foregroundStyle(Color.vNightInk)
                        .padding(.horizontal, VSpacing.s)
                        .frame(minWidth: 48, minHeight: 34)
                        .background(selected ? Color.vNightSelected : .clear, in: .rect(cornerRadius: 9, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.vNightBackground, in: .rect(cornerRadius: VRadius.chip, style: .continuous))
    }

    private func metricButton(_ metric: SleepTrendMetric) -> some View {
        let selected = metric == model.metric
        return Button { model.metric = metric } label: {
            Text(metric.title)
                .vTextStyle(.subheadline).fontWeight(.bold)
                .foregroundStyle(Color.vNightInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? Color.vNightFill : .clear, in: .rect(cornerRadius: VRadius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: VRadius.chip, style: .continuous)
                    .strokeBorder(selected ? Color.vSleep : Color.vNightDashed.opacity(0.6), lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Bars for the trend chart (at most 90, so one Canvas pass is cheap).
struct SleepBarsCanvas: View {
    let bars: [SleepTrendBar?]

    var body: some View {
        Canvas { context, size in
            let count = max(1, bars.count)
            let gap: CGFloat = count <= 10 ? VSpacing.m : (count <= 40 ? 3 : 1)
            let radius: CGFloat = count <= 10 ? 6 : (count <= 40 ? 3 : 1)
            let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for (index, bar) in bars.enumerated() {
                guard let bar else { continue }
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: bar.top * size.height, width: width, height: bar.height * size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(radius, width / 2)), with: .color(Self.color(bar.tone)))
            }
        }
    }

    static func color(_ tone: SleepBarTone) -> Color {
        switch tone {
        case .metTarget: .vSleep
        case .shortOfTarget: .vStageCore
        case .scoreBand(let band): .vSleepScoreBand(band)
        case .window: .vStageREM
        }
    }
}

// MARK: - Insights

struct SleepInsightsSection: View {
    let items: [SleepInsightItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: VSpacing.m) {
                SectionHeader("Insights")
                ForEach(items) { InsightRow($0.text, systemImage: $0.systemImage) }
            }
            .padding(.top, VSpacing.m)
        }
    }
}
