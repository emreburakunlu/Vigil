import SwiftUI

/// Progress · Running: Distance, pace, VO₂ max, personal bests, training load.
struct ProgressRunningView: View {
    var body: some View {
        ScreenPlaceholder(title: "Running", subtitle: "Distance, pace, VO₂ max, personal bests, training load") {}
    }
}

#Preview {
    ProgressRunningView().vigilPreview()
}
