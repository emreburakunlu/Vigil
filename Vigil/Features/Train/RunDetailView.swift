import SwiftUI

/// Run detail (route map, splits, pace/HR/elevation charts, zones, running form).
struct RunDetailView: View {
    let workoutID: UUID

    var body: some View {
        ScreenPlaceholder(title: "Run", subtitle: workoutID.uuidString) {}
    }
}

#Preview {
    RunDetailView(workoutID: UUID()).vigilPreview()
}
