import SwiftUI

// MARK: - Tab glyphs (24 x 24 viewBox, 2 pt round strokes, from Design/Main.dc.html)

private struct TodayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        // Gauge arc: centre (12, 12.5), r 8.5, from lower-left over the top to lower-right.
        path.addArc(center: p(12, 12.5), radius: 8.5 * s, startAngle: .degrees(152), endAngle: .degrees(28), clockwise: false)
        // Needle.
        path.move(to: p(12, 13))
        path.addLine(to: p(16, 9))
        // Hub.
        path.addEllipse(in: CGRect(x: p(10.5, 12).x, y: p(10.5, 12).y, width: 3 * s, height: 3 * s))
        return path
    }
}

private struct TrainGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        for (x, y1, y2) in [(6.5, 6.5, 17.5), (17.5, 6.5, 17.5), (3.5, 9.5, 14.5), (20.5, 9.5, 14.5)] as [(CGFloat, CGFloat, CGFloat)] {
            path.move(to: p(x, y1)); path.addLine(to: p(x, y2))
        }
        path.move(to: p(6.5, 12)); path.addLine(to: p(17.5, 12))
        return path
    }
}

private struct ProgressGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(3, 17)); path.addLine(to: p(9, 11)); path.addLine(to: p(13, 15)); path.addLine(to: p(21, 7))
        path.move(to: p(15, 7)); path.addLine(to: p(21, 7)); path.addLine(to: p(21, 13))
        return path
    }
}

private struct ProfileGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.addEllipse(in: CGRect(x: p(8, 4).x, y: p(8, 4).y, width: 8 * s, height: 8 * s))
        path.move(to: p(4, 21))
        path.addCurve(to: p(12, 15), control1: p(5.5, 17), control2: p(8.5, 15))
        path.addCurve(to: p(20, 21), control1: p(15.5, 15), control2: p(18.5, 17))
        return path
    }
}

/// A tab's glyph drawn with the app's stroke style.
struct VTabGlyph: View {
    let tab: AppTab

    var body: some View {
        Group {
            switch tab {
            case .today: TodayGlyph().stroke(style: style)
            case .sleep: Image(systemName: "moon").font(.system(size: 19, weight: .semibold))
            case .train: TrainGlyph().stroke(style: style)
            case .progress: ProgressGlyph().stroke(style: style)
            case .profile: ProfileGlyph().stroke(style: style)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var style: StrokeStyle { StrokeStyle(lineWidth: 2 * 22 / 24, lineCap: .round, lineJoin: .round) }
}

// MARK: - Floating tab bar

/// The floating pill tab bar (design: 66 pt, 33 pt radius, blur, 6 pt padding, 5 equal items).
///
/// `MainTabView` embeds it; screens don't use it directly. The Sleep tab switches the bar to the night look.
struct VTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isNight: Bool { selection == .sleep }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(6)
        .frame(height: VSize.tabBarHeight)
        // The bar keeps its 66 pt design height; text is capped and, at accessibility sizes, hidden
        // (the large content viewer shows the label on long press).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(isNight ? Color.vNightCardRaised.opacity(0.84) : Color.vTabBarBackground)
            }
        }
        .overlay(Capsule().strokeBorder(isNight ? Color.white.opacity(0.08) : Color.vHairline, lineWidth: VSize.hairline))
        .shadow(color: isNight ? .black.opacity(0.35) : .vTabBarShadow, radius: 15, y: 10)
        .padding(.horizontal, VSpacing.screenGutter)
        .padding(.bottom, VSize.tabBarBottomGap)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        let selectedInk: Color = isNight ? .vNightInk : .vAccent
        let idleInk: Color = isNight ? .vNightInkSecondary : .vInkSecondary
        return Button {
            if reduceMotion { selection = tab } else {
                withAnimation(VMotion.ease(duration: 0.35)) { selection = tab }
            }
        } label: {
            VStack(spacing: 2) {
                VTabGlyph(tab: tab)
                if !typeSize.isAccessibilitySize {
                    Text(tab.title)
                        .font(.vCustom(.body, size: 11, weight: isSelected ? .bold : .semibold, relativeTo: .caption2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(isSelected ? selectedInk : idleInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule().fill(isNight ? Color.white.opacity(0.12) : Color.vAccentTint)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.vPress)
        .accessibilityLabel(tab.title)
        .accessibilityShowsLargeContentViewer {
            Label { Text(tab.title) } icon: { VTabGlyph(tab: tab) }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TabBarPreview: View {
    @State var selection = AppTab.today
    var body: some View {
        ZStack(alignment: .bottom) {
            (selection == .sleep ? Color.vNightBackground : Color.vBackground).ignoresSafeArea()
            VTabBar(selection: $selection)
        }
        .preferredColorScheme(selection == .sleep ? .dark : nil)
    }
}

#Preview("Tab bar") { TabBarPreview() }
