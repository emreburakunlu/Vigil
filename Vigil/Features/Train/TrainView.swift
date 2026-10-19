import SwiftUI

/// Tab 3 · Train with the Run / Lift switch (`AppRouter.trainSegment`). Owner: Train agent.
struct TrainView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            Picker("Training type", selection: $router.trainSegment) {
                Text("Run").tag(TrainSegment.run)
                Text("Lift").tag(TrainSegment.lift)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, VSpacing.screenGutter)
            .padding(.top, VSpacing.s)
            switch router.trainSegment {
            case .run: TrainRunView()
            case .lift: TrainLiftView()
            }
        }
        .background(Color.vBackground)
    }
}

#Preview {
    TrainView().vigilPreview()
}
