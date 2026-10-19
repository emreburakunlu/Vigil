import SwiftUI

/// Lift detail (duration, calories, HR chart, zones, strain, source app).
struct LiftDetailView: View {
    let workoutID: UUID

    var body: some View {
        ScreenPlaceholder(title: "Lift", subtitle: workoutID.uuidString) {}
    }
}

#Preview {
    LiftDetailView(workoutID: UUID()).vigilPreview()
}
