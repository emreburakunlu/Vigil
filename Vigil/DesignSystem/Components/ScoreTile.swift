import SwiftUI

/// Ring + title + coloured caption — one third of the Today score card.
///
/// ```swift
/// ScoreTile(kind: .recovery, progress: 0.78, value: "78", unit: "%", caption: "Green")
/// ScoreTile(kind: .sleep, progress: 0.84, value: "84", caption: "7h 42m")
/// ```
/// The tile combines into one VoiceOver element ("Recovery, 78 percent, Green").
struct ScoreTile: View {
    let kind: VScoreKind
    let progress: Double
    let value: String
    var unit: String?
    let caption: String
    var diameter: CGFloat = VSize.scoreRing
    /// Overrides the colours (e.g. recovery band colour for yellow/red days).
    var colorOverride: Color?

    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(spacing: VSpacing.m) {
            ScoreRing(progress: progress, color: colorOverride ?? kind.color, track: kind.track, diameter: diameter) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(value)
                        .font(.vCustom(.heading, size: diameter * 0.295, weight: .bold, relativeTo: .title))
                        .tracking(-0.02 * diameter * 0.295)
                    if let unit {
                        Text(unit).font(.vCustom(.body, size: diameter * 0.153, weight: .semibold, relativeTo: .callout))
                    }
                }
                .foregroundStyle(surface.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            }
            VStack(spacing: 1) {
                Text(kind.title).vTextStyle(.bodyStrong).foregroundStyle(surface.ink)
                Text(caption).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(colorOverride == nil ? kind.ink : surface.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(kind.title), \(value)\(unit == "%" ? " percent" : ""), \(caption)"))
    }
}

/// The Today score card: three `ScoreTile`s on a large card. Pass the tiles as content.
///
/// ```swift
/// ScoreCard { ScoreTile(kind: .recovery, …); ScoreTile(kind: .sleep, …); ScoreTile(kind: .strain, …) }
/// ```
struct ScoreCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: VSpacing.xxs) { content }
            .padding(.horizontal, VSpacing.m)
            .padding(.top, VSpacing.xxxl)
            .padding(.bottom, VSpacing.cardPadding)
            .vCard(padding: 0, radius: VRadius.cardLarge)
    }
}

#Preview("ScoreCard") {
    ScoreCard {
        ScoreTile(kind: .recovery, progress: 0.78, value: "78", unit: "%", caption: "Green")
        ScoreTile(kind: .sleep, progress: 0.84, value: "84", caption: "7h 42m")
        ScoreTile(kind: .strain, progress: 0.62, value: "62", caption: "Moderate")
    }
    .padding(16)
    .background(Color.vBackground)
}
