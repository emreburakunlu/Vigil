import SwiftUI

/// Onboarding steps in design order (Onb1…Onb7).
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case scores
    case privacy
    case healthAccess
    case aboutYou
    case goals
    case historyImport
}

/// First-launch flow. Finishing sets `settings.onboarding.completed`, which swaps RootView to tabs.
/// Owner: onboarding agent.
struct OnboardingFlowView: View {
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome, .scores, .privacy:
                WelcomeView(page: step, onContinue: advance, onSkip: { step = .healthAccess })
            case .healthAccess:
                HealthAccessView(onContinue: advance)
            case .aboutYou:
                AboutYouView(onContinue: advance)
            case .goals:
                GoalsView(onContinue: advance)
            case .historyImport:
                HistoryImportView()
            }
        }
        .animation(.default, value: step)
    }

    private func advance() {
        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .historyImport
    }
}

#Preview {
    OnboardingFlowView().vigilPreview(onboarded: false, navigation: false)
}
