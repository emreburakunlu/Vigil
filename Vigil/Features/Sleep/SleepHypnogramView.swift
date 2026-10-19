import SwiftUI

/// Stage timeline (Awake / REM / Core / Deep) drawn with Canvas from `SleepHypnogramLayout`.
/// Bars sit at their true start/end times; a hairline connects consecutive stages.
struct SleepHypnogramView: View {
    let layout: SleepHypnogramLayout
    let ticks: [SleepNightPresentation.TickLabel]
    let accessibilityText: String

    @ScaledMetric(relativeTo: .caption) private var laneHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var laneGap: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 46

    private let labelSpacing: CGFloat = VSpacing.s

    private var plotHeight: CGFloat { laneHeight * 4 + laneGap * 3 }
    private var totalHeight: CGFloat { plotHeight + laneGap + laneHeight }

    var body: some View {
        Canvas { context, size in
            let plotX = labelWidth + labelSpacing
            let plotWidth = max(1, size.width - plotX)
            let pitch = laneHeight + laneGap

            // Lane tracks and labels.
            for (index, stage) in SleepStage.hypnogramStages.enumerated() {
                let y = CGFloat(index) * pitch
                let track = CGRect(x: plotX, y: y, width: plotWidth, height: laneHeight)
                context.fill(Path(roundedRect: track, cornerRadius: VRadius.bar), with: .color(Color.vNightSeparator))
                let label = context.resolve(
                    Text(SleepNightPresentation.stageName(stage)).font(.vCaption.weight(.bold)).foregroundStyle(Color.vNightInkSecondary))
                context.draw(label, at: CGPoint(x: 0, y: y + laneHeight / 2), anchor: .leading)
            }

            // Connectors between consecutive stages.
            var links = Path()
            for link in layout.links {
                let x = plotX + link.x * plotWidth
                let y0 = CGFloat(link.fromLane) * pitch + laneHeight / 2
                let y1 = CGFloat(link.toLane) * pitch + laneHeight / 2
                links.move(to: CGPoint(x: x, y: y0))
                links.addLine(to: CGPoint(x: x, y: y1))
            }
            context.stroke(links, with: .color(Color.vNightInkLabel.opacity(0.35)), lineWidth: 1)

            // Stage bars.
            let inset = laneHeight * 3 / 22
            for bar in layout.bars {
                let x = plotX + bar.start * plotWidth
                let width = max(1.5, (bar.end - bar.start) * plotWidth)
                let rect = CGRect(x: x, y: CGFloat(bar.lane) * pitch + inset, width: width, height: laneHeight - inset * 2)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Self.color(for: bar.stage)))
            }

            // Time axis.
            for tick in ticks {
                let text = context.resolve(Text(tick.text).font(.vCaption).foregroundStyle(Color.vNightInkSecondary))
                let width = text.measure(in: size).width
                let centre = plotX + tick.fraction * plotWidth
                let x = min(max(centre, plotX + width / 2), size.width - width / 2)
                context.draw(text, at: CGPoint(x: x, y: plotHeight + laneGap + laneHeight / 2), anchor: .center)
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement()
        .accessibilityLabel("Hypnogram")
        .accessibilityValue(accessibilityText)
    }

    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: .vStageAwake
        case .rem: .vStageREM
        case .core: .vStageCore
        case .deep: .vStageDeep
        case .asleepUnspecified: Color.vStageCore.opacity(0.5)
        case .inBed: .clear
        }
    }
}
