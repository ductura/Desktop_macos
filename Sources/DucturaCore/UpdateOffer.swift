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
        guard let current = version(installed), StrictJSON.isValid(manifest),
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

/// RFC 8259 JSON text, checked byte by byte before JSONSerialization reads it (review FAIL on #15).
/// JSONSerialization also takes text that is not JSON: a trailing comma, other encodings than UTF-8,
/// and per platform more. Here only the grammar of RFC 8259 passes: UTF-8 without a byte order mark,
/// whitespace only from space, tab, LF and CR, nothing after the value, and no escape for an unpaired
/// surrogate (RFC 8259 §8.2 leaves its meaning open, so it fails closed). Nesting is capped.
enum StrictJSON {
    static let maxDepth = 32

    static func isValid(_ data: Data) -> Bool {
        var reader = Reader(bytes: Array(data))
        reader.skipSpace()
        guard reader.value(depth: 0) else { return false }
        reader.skipSpace()
        return reader.index == reader.bytes.count
    }

    struct Reader {
        let bytes: [UInt8]
        var index = 0

        var next: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func skipSpace() {
            while let byte = next, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            guard next == byte else { return false }
            index += 1
            return true
        }

        mutating func value(depth: Int) -> Bool {
            switch next {
            case UInt8(ascii: "{"): return depth < StrictJSON.maxDepth && object(depth: depth + 1)
            case UInt8(ascii: "["): return depth < StrictJSON.maxDepth && array(depth: depth + 1)
            case UInt8(ascii: "\""): return string()
            case UInt8(ascii: "t"): return literal("true")
            case UInt8(ascii: "f"): return literal("false")
            case UInt8(ascii: "n"): return literal("null")
            default: return number()
            }
        }

        mutating func object(depth: Int) -> Bool {
            index += 1
            skipSpace()
            if take(UInt8(ascii: "}")) { return true }
            repeat {
                skipSpace()
                guard string() else { return false }
                skipSpace()
                guard take(UInt8(ascii: ":")) else { return false }
                skipSpace()
                guard value(depth: depth) else { return false }
                skipSpace()
            } while take(UInt8(ascii: ","))
            return take(UInt8(ascii: "}"))
        }

        mutating func array(depth: Int) -> Bool {
            index += 1
            skipSpace()
            if take(UInt8(ascii: "]")) { return true }
            repeat {
                skipSpace()
                guard value(depth: depth) else { return false }
                skipSpace()
            } while take(UInt8(ascii: ","))
            return take(UInt8(ascii: "]"))
        }

        mutating func literal(_ word: String) -> Bool {
            for byte in word.utf8 { guard take(byte) else { return false } }
            return true
        }

        mutating func digits() -> Int {
            let start = index
            while let byte = next, (0x30...0x39).contains(byte) { index += 1 }
            return index - start
        }

        /// `-? (0 | [1-9][0-9]*) (.[0-9]+)? ([eE][+-]?[0-9]+)?`
        mutating func number() -> Bool {
            _ = take(UInt8(ascii: "-"))
            if take(UInt8(ascii: "0")) {
                if let byte = next, (0x30...0x39).contains(byte) { return false }
            } else if digits() == 0 {
                return false
            }
            if take(UInt8(ascii: ".")), digits() == 0 { return false }
            if take(UInt8(ascii: "e")) || take(UInt8(ascii: "E")) {
                if !take(UInt8(ascii: "+")) { _ = take(UInt8(ascii: "-")) }
                if digits() == 0 { return false }
            }
            return true
        }

        mutating func string() -> Bool {
            guard take(UInt8(ascii: "\"")) else { return false }
            while let byte = next {
                switch byte {
                case UInt8(ascii: "\""):
                    index += 1
                    return true
                case UInt8(ascii: "\\"):
                    index += 1
                    guard escape() else { return false }
                case 0x00...0x1F:
                    return false
                case 0x20...0x7F:
                    index += 1
                default:
                    guard utf8() else { return false }
                }
            }
            return false
        }

        /// After a backslash: one of `"\/bfnrt`, or `u` with four hex digits; a high surrogate must be
        /// followed by an escaped low one, and a low one never stands alone.
        mutating func escape() -> Bool {
            guard let byte = next else { return false }
            index += 1
            if Array("\"\\/bfnrt".utf8).contains(byte) { return true }
            guard byte == UInt8(ascii: "u"), let unit = hex4() else { return false }
            if (0xDC00...0xDFFF).contains(unit) { return false }
            guard (0xD800...0xDBFF).contains(unit) else { return true }
            guard take(UInt8(ascii: "\\")), take(UInt8(ascii: "u")), let low = hex4() else { return false }
            return (0xDC00...0xDFFF).contains(low)
        }

        mutating func hex4() -> UInt32? {
            guard index + 4 <= bytes.count else { return nil }
            var unit: UInt32 = 0
            for byte in bytes[index..<index + 4] {
                let digit: UInt8
                switch byte {
                case 0x30...0x39: digit = byte - 0x30
                case 0x41...0x46: digit = byte - 0x41 + 10
                case 0x61...0x66: digit = byte - 0x61 + 10
                default: return nil
                }
                unit = unit << 4 | UInt32(digit)
            }
            index += 4
            return unit
        }

        /// One well-formed UTF-8 sequence of two to four bytes (RFC 3629): no overlong form,
        /// no surrogate, nothing above U+10FFFF.
        mutating func utf8() -> Bool {
            let lead = bytes[index]
            let count: Int, low: UInt8, high: UInt8
            switch lead {
            case 0xC2...0xDF: (count, low, high) = (2, 0x80, 0xBF)
            case 0xE0: (count, low, high) = (3, 0xA0, 0xBF)
            case 0xE1...0xEC, 0xEE...0xEF: (count, low, high) = (3, 0x80, 0xBF)
            case 0xED: (count, low, high) = (3, 0x80, 0x9F)
            case 0xF0: (count, low, high) = (4, 0x90, 0xBF)
            case 0xF1...0xF3: (count, low, high) = (4, 0x80, 0xBF)
            case 0xF4: (count, low, high) = (4, 0x80, 0x8F)
            default: return false
            }
            guard index + count <= bytes.count, (low...high).contains(bytes[index + 1]) else { return false }
            for offset in 2..<count where !(0x80...0xBF).contains(bytes[index + offset]) { return false }
            index += count
            return true
        }
    }
}
