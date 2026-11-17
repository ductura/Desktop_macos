import Foundation

/// What `health` said at launch (DAN-945). `unavailable` covers no answer, a timeout,
/// a status other than 200 and a body that does not decode.
public enum HealthReading: Equatable {
    case unavailable
    case answered(status: String, minClientVersion: String?)
}

public enum ClientVersionDecision: Equatable {
    case open
    case updateRequired(minimum: String)
    case serverUnavailable
}

/// Launch check of the app version against `health.minClientVersion` (DAN-945).
/// The client version is ours (stamped by `build-dmg.sh`), so a malformed one fails closed;
/// a malformed or missing answer from the server never blocks the offline-first web.
public enum ClientVersion {
    /// Static on purpose: the server can ask for an update, but never puts text or a link here.
    public static let updateText = "Ova verzija Ducture više nije podržana. Za nastavak rada nadogradi Ducturu na najnoviju verziju."

    public static func decide(_ reading: HealthReading, clientVersion: String) -> ClientVersionDecision {
        guard case let .answered(status, minimum) = reading, status == "ok" else { return .serverUnavailable }
        guard let minimum else { return .open }
        guard let required = parse(minimum) else { return .serverUnavailable }
        guard let current = parse(clientVersion), !current.lexicographicallyPrecedes(required) else {
            return .updateRequired(minimum: minimum)
        }
        return .open
    }

    /// The address to open, or nil: a client that must update never opens the web.
    public static func webURL(_ decision: ClientVersionDecision, link: URL?) -> URL? {
        if case .updateRequired = decision { return nil }
        return link
    }

    /// Strict `major.minor.patch`: ASCII digits only, no leading zero, no sign, at most 9 digits each.
    static func parse(_ version: String) -> [Int]? {
        let parts = version.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            if part.count > 1 && part.first == 0x30 { return nil }
            numbers.append(part.reduce(0) { $0 * 10 + Int($1 - 0x30) })
        }
        return numbers
    }
}
