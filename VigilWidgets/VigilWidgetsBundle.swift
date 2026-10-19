import SwiftUI
import WidgetKit

/// Home Screen widgets. Owner: widget agent. Data comes only from `WidgetSnapshotStore`
/// (written by the app); the widget never touches HealthKit or SwiftData.
@main
struct VigilWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecoveryWidget()
        DailyScoresWidget()
        WeeklyProgressWidget()
    }
}
