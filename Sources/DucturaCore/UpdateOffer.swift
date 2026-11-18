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
    public static func offer(manifest: Data, architecture: UpdateArchitecture, installed: String) -> UpdateOffer? {
        guard let current = version(installed),
              let top = (try? JSONSerialization.jsonObject(with: manifest)) as? [String: Any],
              top.count == 1, let list = top["packages"] as? [Any], list.count <= 4,
              memberCount(manifest) == 1 + fields.count * list.count else { return nil }
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
                  self.version(version) != nil, isSha256(sha256), isURL(url),
                  pairs.insert("\(system)/\(arch)").inserted else { return nil }
            if system == "macos", arch == architecture.rawValue {
                found = UpdateOffer(version: version, url: url, sha256: sha256, architecture: architecture)
            }
        }
        guard let found, let offered = self.version(found.version),
              current.lexicographicallyPrecedes(offered, by: precedes) else { return nil }
        return found
    }

    static let fields = ["system", "architecture", "version", "url", "sha256"]

    /// `major.minor.patch` as in the contract: ASCII digits, no leading zero, any length.
    /// Kept as digit strings, so no length overflows an Int.
    static func version(_ text: String) -> [[UInt8]]? {
        let parts = text.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false).map(Array.init)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy { (0x30...0x39).contains($0) } && (part.count == 1 || part[0] != 0x30)
        }) else { return nil }
        return parts
    }

    /// Without leading zeros the shorter number is the smaller one; equal lengths compare digit by digit.
    static func precedes(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        a.count != b.count ? a.count < b.count : a.lexicographicallyPrecedes(b)
    }

    /// Object members in the raw text: strings followed by a colon. JSONSerialization keeps one value
    /// for a key given twice (also when spelled with escapes), so a count above the decoded keys means a duplicate.
    static func memberCount(_ data: Data) -> Int {
        var count = 0, inString = false, escaped = false, closed = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false; closed = true }
            } else if byte == 0x22 {
                inString = true
            } else if ![0x20, 0x09, 0x0A, 0x0D].contains(byte) {
                if closed && byte == 0x3A { count += 1 }
                closed = false
            }
        }
        return count
    }

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
