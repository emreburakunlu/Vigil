import SwiftUI

/// First-launch flow. Finishing sets `settings.onboarding.completed`, which swaps RootView to tabs.
/// Owner: onboarding agent.
///
/// Welcome ×3 → Health access (→ denied state) → About you → Goals → History import. Back buttons and
/// the edge-swipe both pop the navigation stack.
struct OnboardingFlowView: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        OnboardingFlowContent(resumeFrom: settingsStore.settings.onboarding)
    }
}

private struct OnboardingFlowContent: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: OnboardingModel

    init(resumeFrom state: OnboardingState) {
        _model = State(initialValue: OnboardingModel(resumeFrom: state))
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(page: .welcome, onContinue: { model.push(.scores) }, onSkip: { model.path = [.healthAccess] })
                .onboardingChrome()
                .navigationDestination(for: OnboardingStep.self) { step in
                    destination(for: step).onboardingChrome()
                }
        }
        .environment(model)
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings with access switched on leaves the denied state.
            if phase == .active, model.path.last == .healthDenied {
                Task { await model.recheckHealthAccess(in: container) }
            }
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome, .scores, .privacy:
            WelcomeView(page: step,
                        onContinue: { model.push(step == .scores ? .privacy : .healthAccess) },
                        onSkip: { model.path = [.healthAccess] })
        case .healthAccess:
            HealthAccessView()
        case .aboutYou:
            AboutYouView(onContinue: { model.push(.goals) })
        case .goals:
            GoalsView(onContinue: { model.push(.historyImport) })
        case .historyImport:
            HistoryImportView()
        case .healthDenied:
            HealthAccessDeniedView(onRetry: { Task { await model.recheckHealthAccess(in: container) } },
                                   onExplain: { model.pop() })
        }
    }
}

#Preview {
    OnboardingFlowView().vigilPreview(.newUser, onboarded: false, navigation: false)
}

#Preview("Dark") {
    OnboardingFlowView().vigilPreview(.newUser, onboarded: false, navigation: false)
        .preferredColorScheme(.dark)
}
