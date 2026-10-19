import SwiftUI

/// Onb6 · Set your goals (sleep, weekly running, weekly lifting).
struct GoalsView: View {
    let onContinue: () -> Void

    var body: some View {
        ScreenPlaceholder(title: "Set your goals", subtitle: "Step 3 of 4") {
            PlaceholderPrimaryButton("Continue", action: onContinue)
        }
    }
}

#Preview {
    GoalsView(onContinue: {}).vigilPreview(onboarded: false)
}
