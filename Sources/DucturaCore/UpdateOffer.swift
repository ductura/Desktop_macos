import Foundation

/// The macOS architectures named in the downloads manifest.
public enum UpdateArchitecture: String {
    case arm64, x64
}

/// A newer macOS package from the body of `downloads.manifest.get` (DAN-1073, part 1073-1).
/// Shape: ductura/server main cecf6c9, `server/contracts/routes/downloads.ts` (S-1H.5, DAN-931).
/// Not wired to the window or the network yet.
public struct UpdateOffer: Equatable {
    public let version: String
    public let url: String
    public let sha256: String
    public let architecture: UpdateArchitecture

    /// The macOS row for `architecture` when it is newer than `installed`, else nil.
    /// Fails closed: if any part of the manifest, in any row, breaks the contract, nothing is offered,
    /// as the server answers 503 rather than a partial list. Two rows for one system and architecture
    /// are ambiguous, so they offer nothing too.
    /// Known limit: JSONSerialization keeps the last of two equal keys (strict reader: DAN-1008).
    public static func offer(manifest: Data, architecture: UpdateArchitecture, installed: String) -> UpdateOffer? {
        guard ClientVersion.parse(installed) != nil,
              let top = (try? JSONSerialization.jsonObject(with: manifest)) as? [String: Any],
              top.count == 1, let list = top["packages"] as? [Any], list.count <= 4 else { return nil }
        var pairs = Set<String>()
        var found: UpdateOffer?
        for item in list {
            guard let row = item as? [String: Any], row.count == fields.count else { return nil }
            var value: [String: String] = [:]
            for field in fields {
                guard let text = row[field] as? String else { return nil }
                value[field] = text
            }
            guard let system = value["system"], let arch = value["architecture"], let version = value["version"],
                  let url = value["url"], let sha256 = value["sha256"],
                  ascii(system, in: ["windows", "macos"]), ascii(arch, in: ["x64", "arm64"]),
                  ClientVersion.parse(version) != nil, isSha256(sha256), isURL(url),
                  pairs.insert("\(system)/\(arch)").inserted else { return nil }
            if system == "macos", arch == architecture.rawValue {
                found = UpdateOffer(version: version, url: url, sha256: sha256, architecture: architecture)
            }
        }
        guard let found, Packaging.isNewer(found.version, than: installed) else { return nil }
        return found
    }

    static let fields = ["system", "architecture", "version", "url", "sha256"]

    /// Byte equality, so no Unicode equivalence lets another spelling through.
    static func ascii(_ text: String, in allowed: [String]) -> Bool {
        allowed.contains { $0.utf8.elementsEqual(text.utf8) }
    }

    /// Exactly 64 lowercase hex digits, counted in UTF-8 bytes.
    static func isSha256(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    static func isURL(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: text.utf16.count)
        return text.utf16.count <= 2048 && urlPattern.firstMatch(in: text, range: range) != nil
    }

    // The server's URL_PATTERN, carried over unchanged: a root path or an https address on a
    // public DNS name, no dot segment, no fragment, no space. END is used instead of `$`,
    // which would also match before a final newline.
    static let urlPattern: NSRegularExpression = {
        let end = #"(?![\s\S])"#
        let notReserved = "(?![a-z0-9]{2}--)"
        let label = "\(notReserved)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
        let host = #"\#(label)(?:\.\#(label))*\.\#(notReserved)[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?"#
        let pchar = #"(?:[A-Za-z0-9._~!$&'()*+,;=:@/?-]|%[0-9A-Fa-f]{2})"#
        let noDots = #"(?![\s\S]*(?:%2[eE]|%00|/\.\.?(?:[/?]|\#(end))))"#
        let hostLength = "(?=[a-z0-9.-]{1,253}/)"
        let notLocal = #"(?!(?:[a-z0-9.-]*\.)?(?:localhost|local|internal|home\.arpa)/)"#
        let pattern = #"^\#(noDots)(?:https://\#(hostLength)\#(notLocal)\#(host))?/(?![/?])\#(pchar)+\#(end)"#
        return try! NSRegularExpression(pattern: pattern)
    }()
}
