import Foundation
import SwiftData

/// Builds the SwiftData `ModelContainer`.
///
/// The store lives in the app's own Application Support directory — **not** the App Group
/// (the widget never reads SwiftData; it reads `WidgetSnapshot`) and never CloudKit.
enum PersistenceController {
    /// Where the store lives.
    enum Storage: Sendable, Equatable {
        /// On-disk store with the given name (`"Vigil"` live, `"Vigil-Mock"` for mock data).
        case onDisk(name: String)
        /// Ephemeral, for previews and tests.
        case inMemory
    }

    static func makeContainer(_ storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VigilSchemaV2.self)
        let configuration: ModelConfiguration
        switch storage {
        case .onDisk(let name):
            configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: false,
                                               allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        case .inMemory:
            configuration = ModelConfiguration("InMemory-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true,
                                               allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: VigilMigrationPlan.self, configurations: [configuration])
    }

    /// On-disk store at an explicit URL (migration tests).
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VigilSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: VigilMigrationPlan.self, configurations: [configuration])
    }

    /// Container that never fails: falls back to in-memory if the on-disk store cannot open
    /// (e.g. corrupted). The failure is logged; the user keeps a working app.
    static func makeContainerOrFallback(_ storage: Storage) -> ModelContainer {
        do {
            return try makeContainer(storage)
        } catch {
            print("Vigil: failed to open store \(storage): \(error). Falling back to in-memory store.")
            do {
                return try makeContainer(.inMemory)
            } catch {
                preconditionFailure("Vigil: cannot create even an in-memory SwiftData store: \(error)")
            }
        }
    }
}
