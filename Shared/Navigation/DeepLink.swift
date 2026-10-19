import Foundation

/// `vigil://` URLs used by widgets, notifications and (later) Spotlight/App Intents.
///
/// | URL                               | Destination                     |
/// |-----------------------------------|---------------------------------|
/// | `vigil://today`                   | Today tab                       |
/// | `vigil://recovery[/yyyy-MM-dd]`   | Today → Recovery detail         |
/// | `vigil://strain[/yyyy-MM-dd]`     | Today → Strain detail           |
/// | `vigil://sleep`                   | Sleep tab                       |
/// | `vigil://sleep/night/yyyy-MM-dd`  | Sleep → night detail            |
/// | `vigil://train`                   | Train tab                       |
/// | `vigil://run/<uuid>`              | Train → run detail              |
/// | `vigil://lift/<uuid>`             | Train → lift detail             |
/// | `vigil://progress`                | Progress tab                    |
/// | `vigil://profile`                 | Profile tab                     |
enum DeepLink: Hashable, Sendable {
    static let scheme = "vigil"

    case today
    case recovery(LocalDay?)
    case strain(LocalDay?)
    case sleep
    case sleepNight(LocalDay)
    case train
    case run(UUID)
    case lift(UUID)
    case progress
    case profile

    /// Builds the canonical URL for the link.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        let (host, path): (String, [String]) = switch self {
        case .today: ("today", [])
        case .recovery(let day): ("recovery", day.map { [$0.isoString] } ?? [])
        case .strain(let day): ("strain", day.map { [$0.isoString] } ?? [])
        case .sleep: ("sleep", [])
        case .sleepNight(let day): ("sleep", ["night", day.isoString])
        case .train: ("train", [])
        case .run(let id): ("run", [id.uuidString])
        case .lift(let id): ("lift", [id.uuidString])
        case .progress: ("progress", [])
        case .profile: ("profile", [])
        }
        components.host = host
        components.path = path.isEmpty ? "" : "/" + path.joined(separator: "/")
        return components.url ?? URL(string: "vigil://today")!
    }

    /// Parses a `vigil://` URL; returns `nil` for foreign or malformed URLs.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch (host, path.count) {
        case ("today", 0): self = .today
        case ("recovery", 0): self = .recovery(nil)
        case ("recovery", 1): guard let day = LocalDay(isoString: path[0]) else { return nil }; self = .recovery(day)
        case ("strain", 0): self = .strain(nil)
        case ("strain", 1): guard let day = LocalDay(isoString: path[0]) else { return nil }; self = .strain(day)
        case ("sleep", 0): self = .sleep
        case ("sleep", 2):
            guard path[0] == "night", let day = LocalDay(isoString: path[1]) else { return nil }
            self = .sleepNight(day)
        case ("train", 0): self = .train
        case ("run", 1): guard let id = UUID(uuidString: path[0]) else { return nil }; self = .run(id)
        case ("lift", 1): guard let id = UUID(uuidString: path[0]) else { return nil }; self = .lift(id)
        case ("progress", 0): self = .progress
        case ("profile", 0): self = .profile
        default: return nil
        }
    }
}
