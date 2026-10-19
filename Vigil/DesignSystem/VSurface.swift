import SwiftUI

/// Which palette shared components draw with. Screens set it once via `.vNightScreen()`
/// (Sleep tab); everything else uses `.standard`.
enum VSurface: Sendable {
    case standard
    case night

    var background: Color { self == .night ? .vNightBackground : .vBackground }
    var card: Color { self == .night ? .vNightCard : .vCard }
    var cardRaised: Color { self == .night ? .vNightCardRaised : .vCardRaised }
    var fill: Color { self == .night ? .vNightFill : .vFill }
    var outline: Color { self == .night ? .vNightSeparator : .vHairline }
    var controlTrack: Color { self == .night ? .vNightCard : .vControlTrack }
    var controlThumb: Color { self == .night ? .vNightSelected : .vControlThumb }
    var ink: Color { self == .night ? .vNightInk : .vInk }
    var inkLabel: Color { self == .night ? .vNightInkLabel : .vInkLabel }
    var inkSecondary: Color { self == .night ? .vNightInkSecondary : .vInkSecondary }
    var inkTertiary: Color { self == .night ? .vNightInkTertiary : .vInkTertiary }
    var accent: Color { self == .night ? .vNightAccent : .vAccent }
    var positive: Color { self == .night ? .vNightPositive : .vPositive }
    var negative: Color { self == .night ? .vNightNegative : .vWarningInk }
}

extension EnvironmentValues {
    /// Palette used by shared components (`.standard` unless a screen opts into `.night`).
    @Entry var vSurface: VSurface = .standard
}

extension View {
    /// Night styling for the Sleep tab screens: night background, night components, dark navigation bar.
    ///
    /// `MainTabView` additionally forces the dark colour scheme while the Sleep tab is selected, so
    /// system chrome (status bar, nav bar, sheets, menus) is dark in both appearances.
    ///
    /// ```swift
    /// ScrollView { … }.vNightScreen()
    /// ```
    func vNightScreen() -> some View {
        self
            .environment(\.vSurface, .night)
            .background(Color.vNightBackground.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Standard screen background (`vBackground`, extends under the safe area).
    func vScreenBackground() -> some View {
        background(Color.vBackground.ignoresSafeArea())
    }
}
