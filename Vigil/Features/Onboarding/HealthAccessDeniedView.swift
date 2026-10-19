import SwiftUI
import UIKit

/// State · Health access off. Explains how to re-enable access in Settings.
struct HealthAccessDeniedView: View {
    let onRetry: () -> Void

    var body: some View {
        ScreenPlaceholder(title: "Vigil can't read Apple Health", subtitle: "Access is turned off, so there's nothing to score.") {
            PlaceholderPrimaryButton("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Try again", action: onRetry)
                .font(.vBodyStrong)
                .foregroundStyle(.vInkSecondary)
        }
    }
}

#Preview {
    HealthAccessDeniedView(onRetry: {}).vigilPreview(.healthAccessDenied)
}
