import SwiftUI

extension TodayPresentation.CaptionTone {
    var color: Color {
        switch self {
        case .recovery: .vRecoveryInk
        case .warning: .vWarningInk
        case .danger: .vDangerInk
        case .sleep: .vSleepInk
        case .strain: .vStrainInk
        case .muted: .vInkSecondary
        }
    }
}

/// Ring colours for a recovery band.
enum TodayBandStyle {
    static func ring(_ band: RecoveryBand) -> Color { Color.vRecoveryBand(band) }

    static func track(_ band: RecoveryBand) -> Color {
        switch band {
        case .green: .vRecoveryTint
        case .yellow: .vWarningTint
        case .red: .vDangerTint
        }
    }
}

/// One ring + title + caption of the Today score card. Optionally a link.
struct TodayScoreTile: View {
    let title: LocalizedStringKey
    let spokenTitle: String
    let display: TodayPresentation.ScoreDisplay
    let ring: Color
    let track: Color
    var route: AppRoute?

    var body: some View {
        if let route {
            NavigationLink(value: route) { content }
                .buttonStyle(.vPress)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: VSpacing.m) {
            ScoreRing(progress: display.progress, color: ring, track: track, diameter: VSize.scoreRing) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(display.value)
                        .font(.vCustom(.heading, size: VSize.scoreRing * 0.295, weight: .bold, relativeTo: .title))
                        .tracking(-0.02 * VSize.scoreRing * 0.295)
                    if let unit = display.unit {
                        Text(unit).font(.vCustom(.body, size: VSize.scoreRing * 0.153, weight: .semibold, relativeTo: .callout))
                    }
                }
                .foregroundStyle(display.hasScore ? Color.vInk : Color.vInkTertiary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            }
            VStack(spacing: 1) {
                Text(title).vTextStyle(.bodyStrong).foregroundStyle(.vInk)
                Text(display.caption)
                    .font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(display.tone.color)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(spokenTitle), \(display.hasScore ? display.value + (display.unit == "%" ? " percent" : "") : "no score"), \(display.caption)"))
        .accessibilityAddTraits(route == nil ? [] : .isButton)
    }
}

/// The three-ring card at the top of Today.
struct TodayScoreCard: View {
    let overview: DayOverview
    let formatter: VigilFormatter
    let isInProgress: Bool

    var body: some View {
        let recovery = TodayPresentation.recovery(overview.recovery)
        let sleep = TodayPresentation.sleep(score: overview.sleepScore, night: overview.sleepNight, formatter: formatter)
        let strain = TodayPresentation.strain(overview.strain, isInProgress: isInProgress)
        let band = overview.recovery?.band ?? .green
        ScoreCard {
            TodayScoreTile(title: "Recovery", spokenTitle: String(localized: "Recovery"), display: recovery,
                           ring: TodayBandStyle.ring(band), track: TodayBandStyle.track(overview.recovery == nil ? .green : band),
                           route: .recovery(overview.day))
            TodayScoreTile(title: "Sleep", spokenTitle: String(localized: "Sleep"), display: sleep,
                           ring: .vSleep, track: .vSleepTint, route: overview.sleepNight == nil ? nil : .sleepNight(overview.day))
            TodayScoreTile(title: "Strain", spokenTitle: String(localized: "Strain"), display: strain,
                           ring: .vStrain, track: .vStrainTint, route: .strain(overview.day))
        }
    }
}

/// Readiness message + the suggested training approach (display only).
struct TodayReadinessCard: View {
    let recovery: RecoveryScore
    let updatedAt: Date
    let formatter: VigilFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.l) {
            HStack {
                OverlineLabel("Readiness")
                Spacer(minLength: VSpacing.s)
                Text("Updated \(formatter.timeOfDay(updatedAt))")
                    .vTextStyle(.footnote)
                    .foregroundStyle(.vInkSecondary)
            }
            Text(recovery.message)
                .font(.vCustom(.body, size: 18, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(.vInk)
                .fixedSize(horizontal: false, vertical: true)
            TodaySuggestionBar(selected: recovery.suggestion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard(radius: VRadius.cardLarge)
        .accessibilityElement(children: .combine)
    }
}

/// Non-interactive Push / Maintain / Take it easy selector.
struct TodaySuggestionBar: View {
    let selected: ReadinessSuggestion

    private func fill(_ suggestion: ReadinessSuggestion) -> Color {
        switch suggestion {
        case .push: .vPositive
        case .maintain: .vWarningInk
        case .takeItEasy: .vDangerInk
        }
    }

    private func icon(_ suggestion: ReadinessSuggestion) -> String? {
        switch suggestion {
        case .push: "chevron.up.2"
        case .maintain: "equal"
        case .takeItEasy: "arrow.down"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ReadinessSuggestion.allCases, id: \.self) { suggestion in
                let isSelected = suggestion == selected
                HStack(spacing: VSpacing.xs) {
                    if isSelected, let icon = icon(suggestion) {
                        Image(systemName: icon).font(.system(size: 12, weight: .heavy)).accessibilityHidden(true)
                    }
                    Text(TodayPresentation.suggestionName(suggestion))
                        .font(.vCustom(.body, size: 14, weight: isSelected ? .bold : .semibold, relativeTo: .callout))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(isSelected ? Color.vCard : Color.vInkSecondary)
                .frame(maxWidth: .infinity, minHeight: VSize.segmentHeight)
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: VRadius.chip, style: .continuous).fill(fill(suggestion)) }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(VSpacing.xxs)
        .background(Color.vBackground, in: .rect(cornerRadius: VRadius.tile, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestion")
    }
}

/// Amber note used for partial and no-data explanations.
struct TodayBanner: View {
    let text: String
    var systemImage = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: VSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.vWarningInk)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(.vCustom(.body, size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(.vWarningInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VSpacing.xxl)
        .padding(.vertical, VSpacing.xl)
        .background(Color.vWarningTint, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
