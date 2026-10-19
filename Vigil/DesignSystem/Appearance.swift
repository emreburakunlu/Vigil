import SwiftUI
import UIKit

extension AppearanceMode {
    /// SwiftUI scheme; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// UIKit style for window overrides.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Applies the in-app appearance override (Settings → Appearance).
///
/// Sets `overrideUserInterfaceStyle` on every window of the app (so UIKit-backed views, sheets
/// and the dynamic `VColor` tokens follow it) and `preferredColorScheme` for SwiftUI.
/// Owner: design-system agent.
struct AppearanceModifier: ViewModifier {
    let mode: AppearanceMode

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(mode.colorScheme)
            .onAppear { apply(mode) }
            .onChange(of: mode) { _, newValue in apply(newValue) }
    }

    private func apply(_ mode: AppearanceMode) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = mode.userInterfaceStyle
            }
        }
    }
}

extension View {
    /// Applies the user's appearance choice. Used once by `RootView`.
    func vigilAppearance(_ mode: AppearanceMode) -> some View {
        modifier(AppearanceModifier(mode: mode))
    }
}
