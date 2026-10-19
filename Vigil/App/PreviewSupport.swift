import SwiftUI

extension View {
    /// Wraps a view for `#Preview`: an in-memory mock `AppContainer` (with `scenario`) injected
    /// into the environment, inside a NavigationStack so `NavigationLink(value:)` works.
    ///
    /// ```swift
    /// #Preview { TodayView().vigilPreview() }
    /// #Preview("Partial") { TodayView().vigilPreview(.partialData) }
    /// ```
    func vigilPreview(_ scenario: MockScenario = .standard, onboarded: Bool = true, navigation: Bool = true) -> some View {
        modifier(VigilPreviewModifier(scenario: scenario, onboarded: onboarded, navigation: navigation))
    }
}

private struct VigilPreviewModifier: ViewModifier {
    @State private var container: AppContainer
    let navigation: Bool

    init(scenario: MockScenario, onboarded: Bool, navigation: Bool) {
        _container = State(initialValue: AppContainer.preview(scenario, onboarded: onboarded))
        self.navigation = navigation
    }

    func body(content: Content) -> some View {
        Group {
            if navigation {
                NavigationStack { content.withAppRoutes() }
            } else {
                content
            }
        }
        .vigilEnvironment(container)
    }
}
