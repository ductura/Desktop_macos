import Foundation

/// A JSON value read by `StrictJSON`. A number keeps its exact source text; an object does not keep key order.
indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

/// Strict RFC 8259 reader with the I-JSON limits of RFC 7493 §2.1 and §2.3 (DAN-1073).
/// Fails closed: anything else, including a repeated key in one object, gives nil.
/// Works on raw bytes, so Linux and Darwin read the same input the same way
/// (`JSONSerialization` keeps the last of repeated keys and accepts a trailing comma).
enum StrictJSON {
    /// Open `[` and `{` together; checked before recursing, so deep input cannot overflow the stack.
    static let maxDepth = 32

    static func parse(_ data: Data) -> JSONValue? {
        let bytes = [UInt8](data)
        // Strict UTF-8 (no overlong form, encoded surrogate or scalar above U+10FFFF); a BOM is never whitespace.
        let invalid = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: true, into: { _ in })
        guard !invalid else { return nil }
        var reader = Reader(bytes: bytes)
        guard let value = reader.value(depth: 0) else { return nil }
        reader.skipSpace()
        return reader.index == bytes.count ? value : nil
    }

    struct Reader {
        let bytes: [UInt8]
        var index = 0

        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func skipSpace() {
            while let b = peek, b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { index += 1 }
        }

        mutating func eat(_ b: UInt8) -> Bool {
            skipSpace()
            guard peek == b else { return false }
            index += 1
            return true
        }

        mutating func literal(_ word: String, _ value: JSONValue) -> JSONValue? {
            let w = Array(word.utf8)
            guard bytes.count - index >= w.count, Array(bytes[index..<index + w.count]) == w else { return nil }
            index += w.count
            return value
        }

        mutating func value(depth: Int) -> JSONValue? {
            skipSpace()
            switch peek {
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                guard depth < StrictJSON.maxDepth else { return nil }
                return peek == UInt8(ascii: "{") ? object(depth: depth + 1) : array(depth: depth + 1)
            case UInt8(ascii: "\""): return string().map(JSONValue.string)
            case UInt8(ascii: "t"): return literal("true", .bool(true))
            case UInt8(ascii: "f"): return literal("false", .bool(false))
            case UInt8(ascii: "n"): return literal("null", .null)
            default: return number()
            }
        }

        mutating func array(depth: Int) -> JSONValue? {
            index += 1
            var items: [JSONValue] = []
            if eat(UInt8(ascii: "]")) { return .array(items) }
            repeat {
                guard let item = value(depth: depth) else { return nil }
                items.append(item)
            } while eat(UInt8(ascii: ","))
            return eat(UInt8(ascii: "]")) ? .array(items) : nil
        }

        mutating func object(depth: Int) -> JSONValue? {
            index += 1
            var members: [String: JSONValue] = [:]
            if eat(UInt8(ascii: "}")) { return .object(members) }
            repeat {
                skipSpace()
                // String == is canonical equivalence: an NFC and an NFD spelling of one key count as a repeat.
                guard peek == UInt8(ascii: "\""), let key = string(), members[key] == nil,
                      eat(UInt8(ascii: ":")), let member = value(depth: depth) else { return nil }
                members[key] = member
            } while eat(UInt8(ascii: ","))
            return eat(UInt8(ascii: "}")) ? .object(members) : nil
        }

        mutating func hex4() -> UInt32? {
            guard bytes.count - index >= 4 else { return nil }
            var code: UInt32 = 0
            for b in bytes[index..<index + 4] {
                guard let digit = Character(Unicode.Scalar(b)).hexDigitValue else { return nil }
                code = code * 16 + UInt32(digit)
            }
            index += 4
            return code
        }

        mutating func string() -> String? {
            index += 1
            var scalars = String.UnicodeScalarView()
            var raw: [UInt8] = []
            func flush() { scalars.append(contentsOf: String(decoding: raw, as: UTF8.self).unicodeScalars); raw = [] }
            while let b = peek {
                index += 1
                switch b {
                case UInt8(ascii: "\""):
                    flush()
                    // I-JSON §2.1: no noncharacter (U+FDD0...U+FDEF, U+xFFFE, U+xFFFF), raw or escaped.
                    let noncharacter = scalars.contains { (0xFDD0...0xFDEF).contains($0.value) || $0.value & 0xFFFE == 0xFFFE }
                    return noncharacter ? nil : String(scalars)
                case 0x00..<0x20: return nil
                case UInt8(ascii: "\\"):
                    guard let e = peek else { return nil }
                    index += 1
                    flush()
                    let simple: [UInt8: Unicode.Scalar] = [0x22: "\"", 0x5C: "\\", 0x2F: "/", 0x62: "\u{8}", 0x66: "\u{C}", 0x6E: "\n", 0x72: "\r", 0x74: "\t"]
                    if let s = simple[e] { scalars.append(s); continue }
                    guard e == UInt8(ascii: "u"), var code = hex4() else { return nil }
                    if (0xD800...0xDBFF).contains(code) {
                        guard peek == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") else { return nil }
                        index += 2
                        guard let low = hex4(), (0xDC00...0xDFFF).contains(low) else { return nil }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let s = Unicode.Scalar(code) else { return nil } // a lone low surrogate
                    scalars.append(s)
                default: raw.append(b) // input is already strict UTF-8
                }
            }
            return nil
        }

        mutating func number() -> JSONValue? {
            let start = index
            func digits() -> Int {
                let from = index
                while let b = peek, b >= 0x30 && b <= 0x39 { index += 1 }
                return index - from
            }
            if peek == UInt8(ascii: "-") { index += 1 }
            if peek == UInt8(ascii: "0") { index += 1 } else if digits() == 0 { return nil }
            if peek == UInt8(ascii: ".") { index += 1; guard digits() > 0 else { return nil } }
            if peek == UInt8(ascii: "e") || peek == UInt8(ascii: "E") {
                index += 1
                if peek == UInt8(ascii: "+") || peek == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { return nil }
            }
            return .number(String(decoding: bytes[start..<index], as: UTF8.self))
        }
    }
}
