import Foundation

extension VigilRepository {
    /// The GPS route of a run (empty for indoor runs or when no route was recorded).
    /// Used by the Train list's mini route previews; `runDetail(id:)` is the full-screen source.
    func trainRoute(for workoutID: UUID) async -> [RouteLocation] {
        (try? await dataSource.runDetails(for: workoutID))?.route ?? []
    }
}
