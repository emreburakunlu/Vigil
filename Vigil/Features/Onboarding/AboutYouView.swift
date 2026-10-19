import SwiftUI

/// Onb5 · About you (age, sex, body weight, units, max HR).
struct AboutYouView: View {
    let onContinue: () -> Void

    var body: some View {
        ScreenPlaceholder(title: "About you", subtitle: "Step 2 of 4") {
            PlaceholderPrimaryButton("Continue", action: onContinue)
        }
    }
}

#Preview {
    AboutYouView(onContinue: {}).vigilPreview(onboarded: false)
}
