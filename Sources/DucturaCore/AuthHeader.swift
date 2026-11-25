import Foundation

/// Session token in the Authorization header (ADR S-1E-e, assumption recorded in the PR).
/// Fail closed: a token that is not a plain token68 value (RFC 7235) gives no header at all,
/// so nothing odd (spaces, CR/LF, quotes) can ever reach the request.
public enum AuthHeader {
    public static let headerName = "Authorization"
    public static let environmentKey = "DUCTURA_SESSION_TOKEN"
    public static let maxLength = 4096
    /// Only API requests carry the token, never HTML pages (same rule as Windows `TokenHeaderHandler`).
    public static let apiPath = "/api/v1/"

    /// `Bearer <token>` or `nil` when the token is missing or not token68.
    public static func value(token: String?) -> String? {
        guard let token, !token.isEmpty, token.utf8.count <= maxLength,
              token.utf8.allSatisfy(isToken68) else { return nil }
        return "Bearer " + token
    }

    /// Token from the process environment (not from arguments: those show up in `ps`), and only
    /// in the functional-test mode `--smoke-window`. A normal launch never reads the environment,
    /// so another process cannot hand the shell a session token that way.
    public static func token(environment: [String: String], options: LaunchOptions) -> String? {
        guard options.smokeWindowOutput != nil else { return nil }
        return environment[environmentKey]
    }

    /// The header goes only on `https://<web host>/api/v1/…` of the checked web address:
    /// same scheme, host and (default) port, no user info, and never on an HTML page.
    public static func headers(token: String?, url: String?, web: WebAddress?) -> [String: String] {
        guard let web, let url, isApiOnOrigin(url: url, web: web),
              let value = value(token: token) else { return [:] }
        return [headerName: value]
    }

    /// Explicit text rules, as in `Navigation`, because `URL` differs between platforms.
    /// Fail closed: a character outside printable ASCII or forbidden in a URI, any `%` escape
    /// in the path, or a `.`/`..` segment (which could climb out of `/api/v1/`) gives `false`.
    static func isApiOnOrigin(url: String, web: WebAddress) -> Bool {
        guard url.utf8.allSatisfy({ (0x21...0x7E).contains($0) && !Navigation.forbidden.contains($0) }),
              let origin = origin(of: web), url.hasPrefix(origin + apiPath) else { return false }
        let path = url.dropFirst(origin.count).prefix { $0 != "?" && $0 != "#" }
        return !path.contains("%")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == "." || $0 == ".." }
    }

    /// `https://<host>` of the checked web address (it has no port, user info or query).
    static func origin(of web: WebAddress) -> String? {
        let rest = web.url.dropFirst("https://".count)
        guard web.url.hasPrefix("https://"), let slash = rest.firstIndex(of: "/") else { return nil }
        return "https://" + String(rest[..<slash])
    }

    static func isToken68(_ b: UInt8) -> Bool {
        switch b {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true // 0-9 A-Z a-z
        case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="): return true
        default: return false
        }
    }
}
