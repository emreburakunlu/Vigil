import Foundation

/// Measurement system chosen in Settings. Canonical storage is always metric (m, kg, °C);
/// convert only at the presentation layer through `VigilFormatter`.
enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Kilograms, kilometres, metres, centimetres, °C.
    case metric
    /// Pounds, miles, feet, inches, °F.
    case imperial

    var id: String { rawValue }
}

/// In-app appearance override. `.system` follows the device setting.
enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}
