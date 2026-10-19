import SwiftUI

/// Welcome pages 1–3 (Onb1 Welcome, Onb2 Three scores, Onb3 Private by design).
struct WelcomeView: View {
    let page: OnboardingStep
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScreenPlaceholder(title: title, subtitle: "Welcome \(page.rawValue + 1) of 3") {
            PlaceholderPrimaryButton(page == .privacy ? "Get started" : "Continue", action: onContinue)
            Button("Skip", action: onSkip)
                .font(.vBodyStrong)
                .foregroundStyle(.vInkSecondary)
        }
    }

    private var title: String {
        switch page {
        case .scores: "Three scores, every morning."
        case .privacy: "Everything stays on your iPhone."
        default: "Sleep, runs and lifts in one place."
        }
    }
}

#Preview {
    WelcomeView(page: .welcome, onContinue: {}, onSkip: {}).vigilPreview(onboarded: false)
}
