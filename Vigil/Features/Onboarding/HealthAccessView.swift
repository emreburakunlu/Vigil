import SwiftUI

/// Onb4 · Connect Apple Health. Requests read access, then continues.
struct HealthAccessView: View {
    @Environment(AppContainer.self) private var container
    let onContinue: () -> Void

    var body: some View {
        ScreenPlaceholder(title: "Connect Apple Health", subtitle: "Step 1 of 4") {
            PlaceholderPrimaryButton("Allow Health access") {
                Task {
                    try? await container.dataSource.requestAuthorization()
                    container.settings.update { $0.onboarding.healthAccessRequestedAt = .now }
                    onContinue()
                }
            }
        }
    }
}

#Preview {
    HealthAccessView(onContinue: {}).vigilPreview(onboarded: false)
}
