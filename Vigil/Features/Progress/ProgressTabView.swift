import SwiftUI

/// Tab 4 · Progress with Running / Lifting / Body (`AppRouter.progressSegment`).
/// Named `ProgressTabView` to avoid clashing with SwiftUI's `ProgressView`. Owner: Progress agent.
struct ProgressTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            Picker("Progress section", selection: $router.progressSegment) {
                Text("Running").tag(ProgressSegment.running)
                Text("Lifting").tag(ProgressSegment.lifting)
                Text("Body").tag(ProgressSegment.body)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.top, VSpacing.s)
            switch router.progressSegment {
            case .running: ProgressRunningView()
            case .lifting: ProgressLiftingView()
            case .body: ProgressBodyView()
            }
        }
        .background(Color.vBackground)
    }
}

#Preview {
    ProgressTabView().vigilPreview()
}
