import Foundation

/// Session token in the Authorization header (ADR S-1E-e, assumption recorded in the PR).
/// Fail closed: a token that is not a plain token68 value (RFC 7235) gives no header at all,
/// so nothing odd (spaces, CR/LF, quotes) can ever reach the request.
public enum AuthHeader {
    public static let headerName = "Authorization"
    public static let environmentKey = "DUCTURA_SESSION_TOKEN"
    public static let maxLength = 4096

    /// `Bearer <token>` or `nil` when the token is missing or not token68.
    public static func value(token: String?) -> String? {
        guard let token, !token.isEmpty, token.utf8.count <= maxLength,
              token.utf8.allSatisfy(isToken68) else { return nil }
        return "Bearer " + token
    }

    /// Token from the process environment (not from arguments: those show up in `ps`).
    public static func token(environment: [String: String]) -> String? {
        environment[environmentKey]
    }

    /// The header goes only on requests to a host from the shell's allow list (`Navigation.stay`).
    public static func headers(token: String?, url: String?, hosts: String?) -> [String: String] {
        guard case .stay = Navigation.decide(url: url, hosts: hosts),
              let value = value(token: token) else { return [:] }
        return [headerName: value]
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
