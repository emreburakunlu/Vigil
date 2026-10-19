import SwiftUI

/// Strain detail for a day (zones, per-workout strain, training load).
struct StrainDetailView: View {
    let day: LocalDay

    var body: some View {
        ScreenPlaceholder(title: "Strain", subtitle: day.isoString) {}
    }
}

#Preview {
    StrainDetailView(day: .today()).vigilPreview()
}
