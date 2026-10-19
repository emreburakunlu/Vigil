#if DEBUG
import Charts
import SwiftUI

/// Developer gallery of every design-system component and token group. Previews: light, dark, night.
struct DesignSystemGallery: View {
    enum Page: String, CaseIterable { case components, tokens, night }

    @State private var page: Page
    @State private var segment = "Run"
    @State private var range = "M"
    @State private var day = LocalDay.today()
    @State private var tab = AppTab.today

    init(page: Page = .components) { _page = State(initialValue: page) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpacing.cardGap) {
                header
                switch page {
                case .components: components
                case .tokens: tokens
                case .night: night
                }
            }
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .modifier(NightIf(isNight: page == .night))
        .overlay(alignment: .bottom) { VTabBar(selection: $tab) }
        .preferredColorScheme(page == .night ? .dark : nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VSpacing.s) {
            Text("Design system").vTextStyle(.largeTitle)
                .foregroundStyle(page == .night ? Color.vNightInk : Color.vInk)
            VSegmentedControl(selection: pageBinding, options: ["components", "tokens", "night"]) { LocalizedStringKey($0.capitalized) }
        }
        .padding(.top, VSpacing.huge)
        .padding(.horizontal, VSpacing.xxs)
    }

    private var pageBinding: Binding<String> {
        Binding(get: { page.rawValue }, set: { page = Page(rawValue: $0) ?? .components })
    }

    // MARK: Components

    @ViewBuilder private var components: some View {
        let today = LocalDay.today()
        DayStrip(
            items: (-6...0).map { DayStripItem(day: today.adding(days: $0), dot: [Color.vRecovery, .vWarning, .vDanger, .vRecovery, .vRecovery, .vWarning, .vRecovery][$0 + 6]) },
            selection: $day
        ) { day = day.adding(days: $0) }
        ScoreCard {
            ScoreTile(kind: .recovery, progress: 0.78, value: "78", unit: "%", caption: "Green")
            ScoreTile(kind: .sleep, progress: 0.84, value: "84", caption: "7h 42m")
            ScoreTile(kind: .strain, progress: 0.62, value: "62", caption: "Moderate")
        }
        SectionHeader("Vitals", trailing: "vs. 30-day baseline")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            VitalTile(name: "HRV", value: "68", unit: "ms", delta: DeltaBadge("+12%", direction: .up, tone: .positive), trend: [58, 61, 57, 63, 60, 64, 62, 66, 68], trendColor: .vRecovery)
            VitalTile(name: "Resting HR", value: "52", unit: "bpm", delta: DeltaBadge("−3 bpm", direction: .down, tone: .positive), trend: [56, 55, 57, 54, 55, 53, 54, 52, 52], trendColor: .vRecovery)
            VitalTile(name: "Respiratory rate", value: "14.6", unit: "br/min", delta: DeltaBadge("Steady", direction: .flat, tone: .neutral), trend: [14.5, 14.7, 14.6, 14.4, 14.7, 14.6])
            VitalTile(name: "Wrist temp", value: "+0.21", unit: "°C", delta: DeltaBadge("+0.21 °C", direction: .up, tone: .caution), trend: [-0.1, 0, -0.05, 0.08, 0.1, 0.21], trendColor: .vWarning)
        }
        HStack(spacing: VSpacing.s) {
            Spacer()
            CircleIconButton(systemImage: "chevron.left", label: "Previous day") {}
            CircleIconButton(systemImage: "calendar", label: "Choose a date") {}
            CircleIconButton(systemImage: "chevron.right", label: "Next day", isDisabled: true) {}
        }
        VSegmentedControl(selection: $segment, options: ["Run", "Lift"]) { LocalizedStringKey($0) }
        VSegmentedControl(selection: $range, options: ["W", "M", "6M", "Y"]) { LocalizedStringKey($0) }
        VCard {
            SectionHeader("Last 7 days", trailing: "Oct 13 – 19", style: .card)
            StatGrid { StatTile("Distance", value: "18.4", unit: "/ 25 km"); StatTile("Time", value: "1:38"); StatTile("Runs", value: "3") }
            ProgressBarGoal("Running", value: 18.4, goal: 25, valueText: "18.4", goalText: "/ 25 km", color: .vRun)
            SegmentedGoalBar(title: "Lifting", done: 2, goal: 3, valueText: "2", goalText: "/ 3 sessions")
        }
        VCard {
            SectionHeader("Heart rate zones", style: .card)
            ZoneBar(zone: 1, fraction: 0.05, duration: "2:10", percentText: "5%")
            ZoneBar(zone: 2, fraction: 0.16, duration: "6:40", percentText: "16%")
            ZoneBar(zone: 3, fraction: 0.45, duration: "19:05", percentText: "45%")
            ZoneBar(zone: 4, fraction: 0.30, duration: "12:48", percentText: "30%")
            ZoneBar(zone: 5, fraction: 0.04, duration: "1:35", percentText: "4%")
        }
        HStack {
            VChip("via Hevy"); VChip("Green", tone: .recovery); VChip("Run", systemImage: "figure.run", tone: .run); VChip("Lift", tone: .lift)
            PRBadge()
        }
        InsightRow("You sleep 35 min more on rest days than after lifting.", systemImage: "chart.line.uptrend.xyaxis")
        VCard {
            SectionHeader("HRV", trailing: "14 days", style: .card)
            GalleryChart().frame(height: 140)
        }
        VCard { EmptyStateView(systemImage: "figure.run", title: "No runs this week", message: "Your next run shows up here automatically.", actionTitle: "Open Health") {} }
        PrimaryButton("Allow Health access", systemImage: "heart.fill") {}
        PrimaryButton("Continue", kind: .inverse) {}
        PrimaryButton("Continue") {}.disabled(true)
        SecondaryButton("Edit goals") {}
        SecondaryButton("Delete all data", isDestructive: true) {}
    }

    // MARK: Tokens

    @ViewBuilder private var tokens: some View {
        swatches("Surfaces", [("Background", .vBackground), ("Card", .vCard), ("Raised", .vCardRaised), ("Fill", .vFill), ("Track", .vControlTrack), ("Thumb", .vControlThumb)])
        swatches("Ink", [("Ink", .vInk), ("Label", .vInkLabel), ("Secondary", .vInkSecondary), ("Tertiary", .vInkTertiary), ("Disabled", .vInkDisabled), ("Inverse", .vInverseFill)])
        swatches("Scores", [("Recovery", .vRecovery), ("RecTint", .vRecoveryTint), ("RecInk", .vRecoveryInk), ("Sleep", .vSleep), ("SleepTint", .vSleepTint), ("SleepInk", .vSleepInk), ("Strain", .vStrain), ("StrainTint", .vStrainTint), ("StrainInk", .vStrainInk)])
        swatches("Training & status", [("Run", .vRun), ("RunSoft", .vRunSoft), ("RunTint", .vRunTint), ("Lift", .vLift), ("LiftSoft", .vLiftSoft), ("Positive", .vPositive), ("Warning", .vWarning), ("WarnTint", .vWarningTint), ("Danger", .vDanger), ("DangerTint", .vDangerTint)])
        swatches("Stages & zones", [("Awake", .vStageAwake), ("REM", .vStageREM), ("Core", .vStageCore), ("Deep", .vStageDeep), ("Z1", .vZone1), ("Z2", .vZone2), ("Z3", .vZone3), ("Z4", .vZone4), ("Z5", .vZone5)])
        swatches("Activity", [("Move", .vMove), ("Exercise", .vExercise), ("Stand", .vStand)])
        VCard {
            Text("Typography").vTextStyle(.headline).foregroundStyle(Color.vInk)
            ForEach(VTextStyle.allCases, id: \.self) { style in
                Text("\(String(describing: style)) 0123456789").vTextStyle(style).foregroundStyle(Color.vInk)
            }
        }
        ConcentricRings(recovery: 0.78, sleep: 0.84, strain: 0.62, diameter: 220)
            .frame(maxWidth: .infinity)
    }

    private func swatches(_ title: String, _ items: [(String, Color)]) -> some View {
        VCard {
            Text(title).vTextStyle(.headline).foregroundStyle(Color.vInk)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(items, id: \.0) { name, color in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color).frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.vHairline))
                        Text(name).font(.vCaption2).foregroundStyle(Color.vInkSecondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    // MARK: Night

    @ViewBuilder private var night: some View {
        ScoreCard {
            ScoreTile(kind: .sleep, progress: 0.84, value: "84", caption: "7h 42m")
        }
        VCard {
            SectionHeader("Sleep stages", style: .card)
            StatGrid { StatTile("Deep", value: "1h 24m"); StatTile("REM", value: "1h 48m"); StatTile("Core", value: "4h 10m") }
            ProgressBarGoal("Average sleep", value: 7.35, goal: 8, valueText: "7h 21m", goalText: "/ 8h", color: .vSleep)
        }
        InsightRow("Your bedtime varied by 48 min this week, up from 31 min last week.", systemImage: "clock")
        VSegmentedControl(selection: $range, options: ["W", "M", "6M", "Y"]) { LocalizedStringKey($0) }
        VStack(spacing: 0) {
            MetricRowList {
                MetricRow(title: "Sleep need", value: "8h 05m", delta: DeltaBadge("+12 min", direction: .up, tone: .positive))
                MetricRow(title: "Bedtime", value: "23:12", delta: DeltaBadge("+18 min", direction: .up, tone: .caution))
            }
        }
        .vNightCard()
    }
}

private struct NightIf: ViewModifier {
    let isNight: Bool
    func body(content: Content) -> some View {
        if isNight { content.vNightScreen() } else { content.vScreenBackground() }
    }
}

private struct GalleryChart: View {
    struct P: Identifiable { let id: Int; let d: Date; let v: Double }
    private let data: [P] = (0..<14).map { P(id: $0, d: Calendar.current.date(byAdding: .day, value: -13 + $0, to: .now) ?? .now, v: 60 + Double(($0 * 37) % 17)) }
    var body: some View {
        Chart {
            VBaselineBand(low: 62, high: 72)
            ForEach(data) { p in
                AreaMark(x: .value("Day", p.d), y: .value("HRV", p.v)).vAreaStyle(.vRecovery)
                LineMark(x: .value("Day", p.d), y: .value("HRV", p.v)).vLineStyle(.vRecovery)
            }
        }
        .vChartAxes(xValues: .stride(by: .day, count: 3))
        .chartYScale(domain: 50...85)
        .accessibilityLabel("HRV over the last 14 days")
    }
}

#Preview("Components") { DesignSystemGallery() }
#Preview("Components dark") { DesignSystemGallery().preferredColorScheme(.dark) }
#Preview("Tokens") { DesignSystemGallery(page: .tokens) }
#Preview("Tokens dark") { DesignSystemGallery(page: .tokens).preferredColorScheme(.dark) }
#Preview("Night") { DesignSystemGallery(page: .night) }
#endif
