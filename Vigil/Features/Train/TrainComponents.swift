import SwiftUI

// Private building blocks shared by the Train screens (candidates for the design system:
// TrainStrainCard, TrainZonesCard, TrainSkeleton, TrainErrorCard).

/// Card with a headline and optional trailing note.
struct TrainCard<Content: View>: View {
    let title: LocalizedStringKey?
    var trailing: String?
    var spacing: CGFloat = VSpacing.xxl
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).vTextStyle(.headline).foregroundStyle(Color.vInk).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: VSpacing.s)
                    if let trailing {
                        Text(trailing).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
    }
}

/// Label over a medium value + small unit: the "Totals" cells.
struct TrainValueCell: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.vCustom(.body, size: 12.5, weight: .semibold, relativeTo: .caption)).foregroundStyle(Color.vInkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: VSpacing.xxs) {
                Text(value).vTextStyle(.statValue).foregroundStyle(Color.vInk)
                if let unit { Text(unit).vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Strain ring + "Strain 41 · Moderate" + training load line.
struct TrainStrainCard: View {
    let strain: WorkoutStrain
    let note: LocalizedStringKey?

    private var levelName: LocalizedStringKey {
        switch strain.level {
        case .light: "Light"
        case .moderate: "Moderate"
        case .high: "High"
        case .allOut: "All out"
        }
    }

    var body: some View {
        HStack(spacing: VSpacing.xxl) {
            ScoreRing(kind: .strain, progress: Double(strain.value) / 100, diameter: 64) {
                Text("\(strain.value)").vTextStyle(.statValue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Strain \(strain.value) · \(Text(levelName))")
                    .vTextStyle(.bodyStrong).foregroundStyle(Color.vInk)
                Text("Training load \(Int(strain.trainingLoad.rounded()))\(note.map { Text(" · ") + Text($0) } ?? Text(""))")
                    .vTextStyle(.footnote).foregroundStyle(Color.vInkSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vCard()
        .accessibilityElement(children: .combine)
    }
}

/// "Heart rate zones" card made of design-system `ZoneBar`s.
struct TrainZonesCard: View {
    let durations: ZoneDurations
    let style: DurationStyle
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let fractions = TrainFormatting.zoneFractions(durations)
        TrainCard(title: "Heart rate zones", spacing: VSpacing.l) {
            ForEach(1...5, id: \.self) { zone in
                ZoneBar(zone: zone, fraction: fractions[zone - 1],
                        duration: VigilFormatter.duration(durations[zone], style: style),
                        percentText: settingsStore.formatter.percent(Int((fractions[zone - 1] * 100).rounded())).text)
            }
        }
    }
}

/// Placeholder block for loading states.
struct TrainSkeleton: View {
    var height: CGFloat = 120
    var body: some View {
        RoundedRectangle(cornerRadius: VRadius.card, style: .continuous)
            .fill(Color.vFill.opacity(0.6))
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// Loading placeholder: a few skeleton cards.
struct TrainSkeletonStack: View {
    var heights: [CGFloat] = [190, 92, 92, 92]
    var body: some View {
        VStack(spacing: VSpacing.l) {
            ForEach(heights.indices, id: \.self) { TrainSkeleton(height: heights[$0]) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// Error card with retry.
struct TrainErrorCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        EmptyStateView(systemImage: "exclamationmark.triangle", title: title, message: message,
                       actionTitle: "Try again", action: retry)
            .vCard()
    }
}
