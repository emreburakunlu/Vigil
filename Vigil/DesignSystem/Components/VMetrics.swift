import SwiftUI

// MARK: - Section header

/// Section title with optional trailing note ("Vitals" ... "vs. 30-day baseline").
///
/// ```swift
/// SectionHeader("Vitals", trailing: "vs. 30-day baseline")
/// SectionHeader("Heart rate zones", style: .card)
/// ```
struct SectionHeader: View {
    enum Style { case section, card }

    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    var style: Style = .section

    @Environment(\.vSurface) private var surface

    init(_ title: LocalizedStringKey, trailing: LocalizedStringKey? = nil, style: Style = .section) {
        self.title = title
        self.trailing = trailing
        self.style = style
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .vTextStyle(style == .section ? .title2 : .headline)
                .foregroundStyle(surface.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: VSpacing.s)
            if let trailing {
                Text(trailing)
                    .vTextStyle(.footnote)
                    .foregroundStyle(surface.inkSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, style == .section ? VSpacing.xxs : 0)
    }
}

/// Small uppercase label above grouped lists ("READINESS", "APPLE HEALTH").
struct OverlineLabel: View {
    let text: LocalizedStringKey
    @Environment(\.vSurface) private var surface

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
            .tracking(0.06 * 13)
            .textCase(.uppercase)
            .foregroundStyle(surface.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Delta badge

/// Direction of a change vs baseline.
enum VDeltaDirection: Sendable {
    case up, down, flat

    var systemImage: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "minus"
        }
    }

    var spokenName: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .flat: "steady"
        }
    }
}

/// How a delta should be coloured.
enum VDeltaTone: Sendable {
    /// Better than baseline (green).
    case positive
    /// Worth a look (amber).
    case caution
    /// Neutral / steady.
    case neutral
}

/// Arrow + text delta versus baseline ("▲ +12%", "▼ −3 bpm", "– Steady").
///
/// ```swift
/// DeltaBadge("+12%", direction: .up, tone: .positive)
/// ```
/// Colour is never the only signal: the arrow shape and the spoken direction carry the meaning too.
struct DeltaBadge: View {
    let text: String
    var direction: VDeltaDirection
    var tone: VDeltaTone

    @Environment(\.vSurface) private var surface

    init(_ text: String, direction: VDeltaDirection, tone: VDeltaTone) {
        self.text = text
        self.direction = direction
        self.tone = tone
    }

    private var color: Color {
        switch tone {
        case .positive: surface.positive
        case .caution: surface.negative
        case .neutral: surface.inkSecondary
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 11, weight: .heavy))
                .accessibilityHidden(true)
            Text(text)
                .font(.vCustom(.body, size: 13, weight: .bold, relativeTo: .footnote))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(direction.spokenName), \(text) versus baseline"))
    }
}

// MARK: - Sparkline

/// Tiny line chart (62 x 22 in the design). Draws left to right on appear.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .vInkTertiary
    var lineWidth: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trim: CGFloat = 0

    var body: some View {
        SparklineShape(values: values)
            .trim(from: 0, to: reduceMotion ? 1 : trim)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: 62, height: 22)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(VMotion.lineDraw) { trim = 1 }
            }
    }
}

struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return path }
        let span = hi - lo == 0 ? 1 : hi - lo
        let inset: CGFloat = 2
        for (index, value) in values.enumerated() {
            let x = rect.minX + inset + (rect.width - inset * 2) * CGFloat(index) / CGFloat(values.count - 1)
            let y = rect.maxY - inset - (rect.height - inset * 2) * CGFloat((value - lo) / span)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

// MARK: - Vital tile / metric row

/// Vitals grid tile: name, big value + unit, delta badge and sparkline (Today "Vitals").
///
/// ```swift
/// VitalTile(name: "HRV", value: "68", unit: "ms", delta: DeltaBadge("+12%", direction: .up, tone: .positive), trend: [58, 61, 68], trendColor: .vRecovery)
/// ```
struct VitalTile: View {
    let name: LocalizedStringKey
    let value: String
    var unit: String?
    var delta: DeltaBadge?
    var trend: [Double] = []
    var trendColor: Color = .vInkTertiary

    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Text(name).font(.vCustom(.body, size: 13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(surface.inkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: VSpacing.xxs) {
                Text(value)
                    .font(.vCustom(.heading, size: 26, weight: .bold, relativeTo: .title))
                    .tracking(-0.02 * 26)
                    .foregroundStyle(surface.ink)
                if let unit { Text(unit).vTextStyle(.footnote).foregroundStyle(surface.inkSecondary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack(spacing: VSpacing.xs) {
                if let delta { delta }
                Spacer(minLength: 0)
                if !trend.isEmpty { Sparkline(values: trend, color: trendColor) }
            }
        }
        .padding(.init(top: VSpacing.cardPaddingCompact, leading: VSpacing.cardPaddingCompact, bottom: VSpacing.l, trailing: VSpacing.cardPaddingCompact))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface.card, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(surface.outline, lineWidth: VSize.hairline))
        .shadow(color: .vShadow, radius: 1, y: 1)
        .accessibilityElement(children: .combine)
    }
}

/// Full-width list row: label (+ optional sub-label) on the left, value/unit and delta on the right.
/// Rows inside a card are divided with `Divider`-style `vSeparator` lines by `MetricRowList`.
struct MetricRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let value: String
    var unit: String?
    var delta: DeltaBadge?
    var showsChevron = false

    @Environment(\.vSurface) private var surface

    var body: some View {
        HStack(spacing: VSpacing.l) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).vTextStyle(.body).foregroundStyle(surface.ink)
                if let subtitle { Text(subtitle).vTextStyle(.caption).foregroundStyle(surface.inkSecondary) }
            }
            Spacer(minLength: VSpacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: VSpacing.xxs) {
                    Text(value).vTextStyle(.bodyStrong).foregroundStyle(surface.inkLabel)
                    if let unit { Text(unit).vTextStyle(.footnote).foregroundStyle(surface.inkSecondary) }
                }
                if let delta { delta }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(surface.inkTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Stacks rows with hairline separators (last row has none).
struct MetricRowList<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index]
                    if index < subviews.count - 1 {
                        Rectangle().fill(surface == .night ? Color.vNightSeparator : Color.vSeparator).frame(height: VSize.hairline)
                    }
                }
            }
        }
    }
}

// MARK: - Stat tile & grid

/// Label over a big number: "Distance 18.4 / 25 km".
///
/// ```swift
/// StatTile("Distance", value: "18.4", unit: "/ 25 km")
/// ```
struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String?
    var valueStyle: Style = .large

    enum Style { case large, compact }

    @Environment(\.vSurface) private var surface

    init(_ label: LocalizedStringKey, value: String, unit: String? = nil, style: Style = .large) {
        self.label = label
        self.value = value
        self.unit = unit
        self.valueStyle = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.vCustom(.body, size: 12.5, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(surface.inkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: VSpacing.xxs) {
                Text(value)
                    .font(valueStyle == .large
                        ? .vCustom(.heading, size: 26, weight: .bold, relativeTo: .title)
                        : .vCustom(.body, size: 18, weight: .heavy, relativeTo: .headline))
                    .foregroundStyle(surface.ink)
                if let unit {
                    Text(unit).vTextStyle(.subheadline).foregroundStyle(surface.inkSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Grid of `StatTile`s on a card or plain.
struct StatGrid<Content: View>: View {
    var columns = 3
    var spacing: CGFloat = VSpacing.s
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .topLeading), count: columns), alignment: .leading, spacing: VSpacing.xl) {
            content
        }
    }
}

// MARK: - Progress bars

/// Goal progress: "Running  18.4 / 25 km" over a 10 pt bar.
///
/// ```swift
/// ProgressBarGoal("Running", value: 18.4, goal: 25, valueText: "18.4", goalText: "/ 25 km", color: .vRun)
/// ```
struct ProgressBarGoal: View {
    let title: LocalizedStringKey
    let value: Double
    let goal: Double
    let valueText: String
    let goalText: String
    var color: Color = .vAccent

    @Environment(\.vSurface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    init(_ title: LocalizedStringKey, value: Double, goal: Double, valueText: String, goalText: String, color: Color = .vAccent) {
        self.title = title
        self.value = value
        self.goal = goal
        self.valueText = valueText
        self.goalText = goalText
        self.color = color
    }

    private var fraction: Double { goal > 0 ? min(max(value / goal, 0), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).vTextStyle(.bodyStrong).foregroundStyle(surface.ink)
                Spacer(minLength: VSpacing.s)
                GoalValueText(value: valueText, goal: goalText)
            }
            VProgressTrack(fraction: (drawn || reduceMotion) ? fraction : 0, color: color)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(VMotion.ease(duration: 0.9).delay(0.2)) { drawn = true }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(valueText) \(goalText), \(Int((fraction * 100).rounded())) percent of goal"))
    }
}

/// "18.4 / 25 km": strong value followed by a lighter goal.
private struct GoalValueText: View {
    let value: String
    let goal: String
    @Environment(\.vSurface) private var surface

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: VSpacing.xxs) {
            Text(value).vTextStyle(.bodyStrong).foregroundStyle(surface.ink)
            Text(goal).vTextStyle(.callout).foregroundStyle(surface.inkSecondary)
        }
    }
}

/// The bare 10 pt rounded track + fill.
struct VProgressTrack: View {
    let fraction: Double
    var color: Color
    var height: CGFloat = VSize.progressBarHeight

    @Environment(\.vSurface) private var surface

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(surface.fill)
                Capsule().fill(color).frame(width: max(fraction > 0 ? height : 0, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Segment-count goal ("Lifting 2 / 3 sessions"): `goal` pills, `done` of them filled.
struct SegmentedGoalBar: View {
    let title: LocalizedStringKey
    let done: Int
    let goal: Int
    let valueText: String
    let goalText: String
    var color: Color = .vLift

    @Environment(\.vSurface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).vTextStyle(.bodyStrong).foregroundStyle(surface.ink)
                Spacer(minLength: VSpacing.s)
                GoalValueText(value: valueText, goal: goalText)
            }
            HStack(spacing: VSpacing.xs) {
                ForEach(0..<max(goal, 1), id: \.self) { index in
                    Capsule().fill(index < done ? color : surface.fill).frame(height: VSize.progressBarHeight)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(done) of \(goal) \(goalText)"))
    }
}

/// Heart-rate zone row: "Z3 ▮▮▮▮▮▮ 19:05 45%".
///
/// ```swift
/// ZoneBar(zone: 3, fraction: 0.45, duration: "19:05", percentText: "45%")
/// ```
struct ZoneBar: View {
    let zone: Int
    /// 0...1 share of the workout.
    let fraction: Double
    let duration: String
    let percentText: String

    @Environment(\.vSurface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        HStack(spacing: VSpacing.m) {
            Text("Z\(zone)")
                .font(.vCustom(.body, size: 13, weight: .heavy, relativeTo: .footnote))
                .foregroundStyle(surface.inkLabel)
                .frame(width: 30, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(surface == .night ? Color.vNightFill : Color.vBackground)
                    Capsule().fill(Color.vZone(zone))
                        .frame(width: max(fraction > 0 ? VSize.zoneBarHeight : 0, proxy.size.width * ((drawn || reduceMotion) ? min(max(fraction, 0), 1) : 0)))
                }
            }
            .frame(height: VSize.zoneBarHeight)
            Text(duration)
                .font(.vCustom(.body, size: 14, weight: .heavy, relativeTo: .subheadline))
                .foregroundStyle(surface.ink)
                .frame(minWidth: 48, alignment: .trailing)
            Text(percentText)
                .vTextStyle(.footnote)
                .foregroundStyle(surface.inkSecondary)
                .frame(minWidth: 38, alignment: .trailing)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(VMotion.barGrow) { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Zone \(zone)"))
        .accessibilityValue(Text("\(duration), \(percentText)"))
    }
}

#Preview("Metrics") {
    ScrollView {
        VStack(spacing: 16) {
            SectionHeader("Vitals", trailing: "vs. 30-day baseline")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                VitalTile(name: "HRV", value: "68", unit: "ms", delta: DeltaBadge("+12%", direction: .up, tone: .positive), trend: [58, 61, 57, 63, 60, 64, 62, 66, 68], trendColor: .vRecovery)
                VitalTile(name: "Resting HR", value: "52", unit: "bpm", delta: DeltaBadge("−3 bpm", direction: .down, tone: .positive), trend: [56, 55, 57, 54, 55, 53, 54, 52, 52], trendColor: .vRecovery)
                VitalTile(name: "Respiratory rate", value: "14.6", unit: "br/min", delta: DeltaBadge("Steady", direction: .flat, tone: .neutral), trend: [14.5, 14.7, 14.6, 14.4, 14.7, 14.6])
                VitalTile(name: "Wrist temp", value: "+0.21", unit: "°C", delta: DeltaBadge("+0.21 °C", direction: .up, tone: .caution), trend: [-0.1, 0, -0.05, 0.08, 0.1, 0.21], trendColor: .vWarning)
            }
            VCard {
                StatGrid { StatTile("Distance", value: "18.4", unit: "/ 25 km"); StatTile("Time", value: "1:38"); StatTile("Runs", value: "3") }
                ProgressBarGoal("Running", value: 18.4, goal: 25, valueText: "18.4", goalText: "/ 25 km", color: .vRun)
                SegmentedGoalBar(title: "Lifting", done: 2, goal: 3, valueText: "2", goalText: "/ 3 sessions")
                ZoneBar(zone: 3, fraction: 0.45, duration: "19:05", percentText: "45%")
                ZoneBar(zone: 5, fraction: 0.04, duration: "1:35", percentText: "4%")
            }
            VCard {
                MetricRowList {
                    MetricRow(title: "Age", value: "21", showsChevron: true)
                    MetricRow(title: "Body weight", subtitle: "Synced from Health", value: "74.2", unit: "kg", delta: DeltaBadge("−0.4 kg", direction: .down, tone: .neutral))
                }
            }
        }
        .padding(16)
    }
    .background(Color.vBackground)
}
