import SwiftUI

/// Recovery detail for a day (score, factor contributions, 30-day trend, HRV/RHR trends).
struct RecoveryDetailView: View {
    let day: LocalDay

    var body: some View {
        ScreenPlaceholder(title: "Recovery", subtitle: day.isoString) {}
    }
}

#Preview {
    RecoveryDetailView(day: .today()).vigilPreview()
}
