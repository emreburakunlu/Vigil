import Foundation
import Observation
import SwiftData
import SwiftUI

/// Observable source of truth for `VigilSettings`, persisted in SwiftData.
///
/// Read `settings` from views (`@Environment(SettingsStore.self) private var settingsStore`) and
/// write through `update { $0.units = .imperial }` or `binding(\.units)`.
@MainActor
@Observable
final class SettingsStore {
    /// Current settings (always valid; defaults on first launch).
    private(set) var settings: VigilSettings

    /// Strong reference: a `ModelContext` does not keep its container alive.
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var record: SettingsRecord
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<SettingsRecord>(sortBy: [SortDescriptor(\.updatedAt)]))) ?? []
        if let first = existing.first {
            record = first
            // Defensive: collapse accidental duplicates into the oldest row.
            existing.dropFirst().forEach { context.delete($0) }
        } else {
            let fresh = SettingsRecord()
            context.insert(fresh)
            record = fresh
        }
        settings = record.value
        try? context.save()
    }

    /// Mutates and persists settings. No-op when nothing changed.
    func update(_ change: (inout VigilSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        record.apply(next)
        save()
    }

    /// A SwiftUI binding to one settings field (for pickers, toggles, steppers).
    func binding<Value>(_ keyPath: WritableKeyPath<VigilSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { newValue in self.update { $0[keyPath: keyPath] = newValue } })
    }

    /// Restores defaults (used by tests and "Delete local data" when profile should be cleared too).
    func resetToDefaults() {
        update { $0 = .default }
    }

    /// Formatter for the current unit system.
    var formatter: VigilFormatter { settings.formatter }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Vigil: failed to save settings: \(error)")
        }
    }
}
