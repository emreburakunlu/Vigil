import SwiftUI

/// Inset tile surface inside night cards (design `#1F2342`: the raised fill blended over the card).
extension ShapeStyle where Self == Color {
    static var sleepTile: Color { Color.vNightFill.opacity(0.55) }
}

// MARK: - Score

struct SleepScoreCard: View {
    let night: SleepNightPresentation

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xxl + VSpacing.xxs) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: VSpacing.xxxl))
                                                      : AnyLayout(HStackLayout(spacing: VSpacing.xxxl))
            layout {
                ring
                total
            }
            HStack(spacing: VSpacing.m) {
                timeTile("moon", "Bedtime", night.bedtime)
                timeTile("sun.max", "Woke up", night.wakeTime)
            }
            Rectangle().fill(Color.vNightSeparator).frame(height: VSize.hairline)
            HStack(alignment: .top, spacing: VSpacing.s) {
                StatTile("In bed", value: night.inBed, style: .compact)
                StatTile("Efficiency", value: night.efficiency, style: .compact)
                StatTile("Interruptions", value: night.interruptions, style: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vNightCard(padding: VSpacing.xxxl, radius: VRadius.cardLarge)
    }

    private var ring: some View {
        ScoreRing(progress: Double(night.scoreValue) / 100, color: .vSleepScoreBand(night.band), track: .vNightFill, diameter: ringSize, animated: false) {
            VStack(spacing: 0) {
                Text("\(night.scoreValue)")
                    .font(.vCustom(.heading, size: 38, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Color.vNightInk)
                Text("SCORE")
                    .font(.vCustom(.body, size: 12, weight: .bold, relativeTo: .caption))
                    .tracking(0.5)
                    .foregroundStyle(Color.vNightInkSecondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(night.scoreAccessibility)
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Text("Total sleep")
                .font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
                .tracking(0.65)
                .textCase(.uppercase)
                .foregroundStyle(Color.vNightInkSecondary)
            Text(night.totalSleep)
                .font(.vCustom(.heading, size: 32, weight: .bold, relativeTo: .title))
                .foregroundStyle(Color.vNightInk)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            VProgressTrack(fraction: night.targetProgress, color: .vSleepScoreBand(night.band), height: 8)
            Text(night.targetCaption)
                .vTextStyle(.footnote)
                .foregroundStyle(Color.vNightInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func timeTile(_ icon: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: VSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.vNightInkSecondary)
                .accessibilityHidden(true)
            StatTile(title, value: value, style: .compact)
        }
        .padding(VSpacing.l)
        .background(.sleepTile, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
    }
}

// MARK: - Stages

struct SleepStagesCard: View {
    let night: SleepNightPresentation
    /// Night detail labels the start, the end and the hours between; the tab shows whole hours only.
    var showsEdgeTicks = false

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xl) {
            SectionHeader("Sleep stages", style: .card)
            if let layout = night.hypnogram {
                SleepHypnogramView(layout: layout, ticks: showsEdgeTicks ? night.hypnogramEdgeTicks : night.hypnogramTicks, accessibilityText: night.hypnogramAccessibility)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: VSpacing.m), GridItem(.flexible())], spacing: VSpacing.m) {
                    ForEach(night.stages) { SleepStageTile(tile: $0) }
                }
                .padding(.top, VSpacing.xxs)
            } else {
                Text("Stage data isn't available for this night.")
                    .vTextStyle(.callout)
                    .foregroundStyle(Color.vNightInkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vNightCard(padding: VSpacing.xxl, radius: VRadius.cardLarge)
    }
}

struct SleepStageTile: View {
    let tile: SleepNightPresentation.StageTile

    var body: some View {
        let color = SleepHypnogramView.color(for: tile.stage)
        VStack(alignment: .leading, spacing: VSpacing.s) {
            HStack(spacing: VSpacing.xs + 1) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
                Text(tile.name).vTextStyle(.subheadline).fontWeight(.bold).foregroundStyle(Color.vNightInkLabel)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(tile.time).font(.vCustom(.body, size: 19, weight: .heavy, relativeTo: .headline)).foregroundStyle(Color.vNightInk)
                Spacer(minLength: VSpacing.xxs)
                Text(tile.percent).font(.vCustom(.body, size: 15, weight: .bold, relativeTo: .callout)).foregroundStyle(color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.vNightFill)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.vNightInk.opacity(0.13))
                        .frame(width: max(0, (tile.bandEnd - tile.bandStart) * width), height: 12)
                        .offset(x: tile.bandStart * width)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: 4, height: 14)
                        .offset(x: min(max(0, tile.markFraction * width - 2), width - 4))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            Text(tile.typical).vTextStyle(.caption).foregroundStyle(Color.vNightInkTertiary)
        }
        .padding(VSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.sleepTile, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.name), \(tile.time), \(tile.percent) of the night. \(tile.typical)")
    }
}

// MARK: - Vitals

struct SleepVitalsCard: View {
    let night: SleepNightPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.xxs) {
            SectionHeader("Sleep vitals", trailing: "Baseline", style: .card)
            MetricRowList {
                ForEach(night.vitals) { row in
                    NavigationLink(value: AppRoute.metric(row.metric, night.day)) {
                        SleepVitalRowView(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vNightCard(padding: VSpacing.xxl, radius: VRadius.cardLarge)
    }
}

struct SleepVitalRowView: View {
    let row: SleepNightPresentation.VitalRow

    var body: some View {
        HStack(spacing: VSpacing.m) {
            Text(row.name).font(.vCustom(.body, size: 15, weight: .semibold, relativeTo: .callout)).foregroundStyle(Color.vNightInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let value = row.value {
                HStack(spacing: VSpacing.xxs) {
                    Text(value).vTextStyle(.bodyStrong).fontWeight(.heavy).foregroundStyle(Color.vNightInk)
                    if let arrow = row.arrow {
                        Image(systemName: arrow == .up ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(row.tone == .positive ? Color.vNightPositive : Color.vNightNegative)
                    }
                }
            } else {
                Text("Not available").vTextStyle(.footnote).foregroundStyle(Color.vNightInkTertiary)
            }
            Text(row.baseline ?? "–")
                .vTextStyle(.footnote)
                .foregroundStyle(Color.vNightInkSecondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

// MARK: - No data

/// "No sleep recorded" card (State · No sleep). `nightBefore` adds the "See the night before" button.
struct SleepNoSleepCard: View {
    var isLastNight = true
    var nightBefore: LocalDay?

    var body: some View {
        VStack(spacing: VSpacing.xl) {
            Image(systemName: "moon")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.vNightInkTertiary)
                .frame(width: 96, height: 96)
                .overlay(Circle().strokeBorder(Color.vNightDashed, style: StrokeStyle(lineWidth: 3, dash: [6, 6])))
                .accessibilityHidden(true)
            Text("No sleep recorded")
                .vTextStyle(.title2).fontWeight(.bold)
                .foregroundStyle(Color.vNightInk)
                .accessibilityAddTraits(.isHeader)
            Text(isLastNight
                 ? "Apple Health has no sleep data for last night. Today's Recovery uses HRV and resting heart rate only."
                 : "Apple Health has no sleep data for this night.")
                .vTextStyle(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.vNightInkLabel)
            VStack(alignment: .leading, spacing: VSpacing.m) {
                reason("Your watch wasn't worn to bed")
                reason("The battery ran out overnight")
                reason("Sleep tracking is off in the Watch app")
            }
            .padding(.horizontal, VSpacing.xxl)
            .padding(.vertical, VSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.sleepTile, in: .rect(cornerRadius: 18, style: .continuous))
            if let nightBefore {
                NavigationLink(value: AppRoute.sleepNight(nightBefore)) {
                    Text("See the night before")
                        .vTextStyle(.bodyStrong).fontWeight(.bold)
                        .foregroundStyle(Color.vNightBackground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.vNightInk, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.vPress)
            }
        }
        .frame(maxWidth: .infinity)
        .vNightCard(padding: VSpacing.xxxl, radius: VRadius.cardLarge)
    }

    private func reason(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VSpacing.m) {
            Text("•").foregroundStyle(Color.vNightAccent)
            Text(text).vTextStyle(.subheadline).foregroundStyle(Color.vNightInkLabel)
        }
    }
}

/// Compact sleep-debt row used on the no-sleep screen.
struct SleepDebtSummaryRow: View {
    let debt: SleepDebt
    let formatter: VigilFormatter

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: VSpacing.xxxs) {
                Text("Sleep debt").vTextStyle(.bodyStrong).fontWeight(.bold).foregroundStyle(Color.vNightInk)
                Text("\(debt.nightsRecorded) of the last 7 nights recorded")
                    .vTextStyle(.footnote).foregroundStyle(Color.vNightInkSecondary)
            }
            Spacer(minLength: VSpacing.s)
            Text(formatter.duration(debt.total))
                .font(.vCustom(.heading, size: 24, weight: .bold, relativeTo: .title2))
                .foregroundStyle(Color.vNightNegative)
        }
        .vNightCard(padding: VSpacing.xxl, radius: 22)
        .accessibilityElement(children: .combine)
    }
}
