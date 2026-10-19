import SwiftUI

/// State · No runs this week (embedded by `TrainRunView`).
struct NoRunsStateView: View {
    var body: some View {
        ScreenPlaceholder(title: "No runs this week", subtitle: "Runs from any app that saves to Health appear here.") {}
    }
}

#Preview {
    NoRunsStateView().vigilPreview(.noRunsThisWeek)
}
