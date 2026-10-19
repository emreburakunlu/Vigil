import Foundation

/// How this process should be wired, derived from launch arguments and environment.
///
/// | Condition                                   | Data  | Store                 |
/// |---------------------------------------------|-------|-----------------------|
/// | SwiftUI preview (`XCODE_RUNNING_FOR_PREVIEWS`) | mock  | in-memory             |
/// | Unit tests (`XCTestConfigurationFilePath`)  | mock  | in-memory             |
/// | `-VigilLiveData`                            | live  | on-disk "Vigil"       |
/// | `-VigilMockData` or running in Simulator    | mock  | on-disk "Vigil-Mock"  |
/// | otherwise (device)                          | live  | on-disk "Vigil"       |
///
/// Extra flags: `-VigilMockScenario <MockScenario>`, `-VigilSkipOnboarding`,
/// `-VigilResetData` (wipe local store at launch), `-VigilInMemoryStore`.
struct LaunchConfiguration: Sendable, Equatable {
    enum DataMode: Sendable, Equatable {
        case live
        case mock(MockScenario)
    }

    var dataMode: DataMode
    var storage: PersistenceController.Storage
    var skipOnboarding: Bool
    var resetData: Bool

    var isMock: Bool { if case .mock = dataMode { true } else { false } }

    static let liveStoreName = "Vigil"
    static let mockStoreName = "Vigil-Mock"

    /// Configuration for the running process.
    static var current: LaunchConfiguration {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return resolve(arguments: ProcessInfo.processInfo.arguments,
                       environment: ProcessInfo.processInfo.environment,
                       isSimulator: isSimulator)
    }

    /// Pure resolution logic (unit-tested).
    static func resolve(arguments: [String], environment: [String: String], isSimulator: Bool) -> LaunchConfiguration {
        let scenario = value(after: "-VigilMockScenario", in: arguments).flatMap(MockScenario.init(rawValue:)) ?? .standard
        let isPreview = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let isTesting = environment["XCTestConfigurationFilePath"] != nil
        let skipOnboarding = arguments.contains("-VigilSkipOnboarding")
        let resetData = arguments.contains("-VigilResetData")

        if isPreview || isTesting {
            return LaunchConfiguration(dataMode: .mock(scenario), storage: .inMemory, skipOnboarding: skipOnboarding, resetData: false)
        }
        let useMock = !arguments.contains("-VigilLiveData") && (arguments.contains("-VigilMockData") || isSimulator)
        let storage: PersistenceController.Storage = arguments.contains("-VigilInMemoryStore")
            ? .inMemory
            : .onDisk(name: useMock ? mockStoreName : liveStoreName)
        return LaunchConfiguration(dataMode: useMock ? .mock(scenario) : .live, storage: storage,
                                   skipOnboarding: skipOnboarding, resetData: resetData)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
