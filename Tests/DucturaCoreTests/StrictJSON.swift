import Foundation

/// A JSON value with exact data (DAN-1008): a number stays its token text (never a Double, so
/// 1.0000000000000001 is not 1) and a string stays UTF-16 units, so a lone surrogate survives and
/// object keys compare unit by unit, as in JavaScript.
indirect enum JSONValue: Equatable {
    case null, bool(Bool), number(String), string([UInt16]), array([JSONValue]), object([[UInt16]: JSONValue])
}

struct StrictJSONError: Error, Equatable, CustomStringConvertible {
    enum Kind: Equatable { case encoding, syntax, duplicateKey, tooDeep }

    let kind: Kind
    /// Offset in UTF-16 units of the decoded text (0 for an encoding error).
    let at: Int

    var description: String {
        let text: String
        switch kind {
        case .encoding: text = "JSON nije ispravan UTF-8 bez BOM-a i bez NUL znaka"
        case .syntax: text = "JSON nije ispravan po RFC 8259"
        case .duplicateKey: text = "JSON objekt ima dvostruki ključ"
        case .tooDeep: text = "JSON je ugniježđen dublje od \(StrictJSON.maxDepth) razina"
        }
        return "\(text), UTF-16 jedinica \(at)"
    }
}

/// Strict RFC 8259 reader for contract vectors, test-only. Strict UTF-8 without BOM or NUL; only
/// SP, TAB, LF and CR between tokens; a duplicate key at any level and nesting deeper than
/// `maxDepth` are errors. Every refusal is a thrown StrictJSONError, never a trap.
struct StrictJSON {
    static let maxDepth = 64
    static let escapes: [UInt16: UInt16] = [
        0x22: 0x22, 0x5C: 0x5C, 0x2F: 0x2F, 0x62: 0x08, 0x66: 0x0C, 0x6E: 0x0A, 0x72: 0x0D, 0x74: 0x09,
    ]

    let units: [UInt16]
    var at = 0

    static func parse(_ data: Data) throws -> JSONValue {
        var units: [UInt16] = []
        let failed = transcode(data.makeIterator(), from: UTF8.self, to: UTF16.self, stoppingOnError: true) { units.append($0) }
        guard !failed, units.first != 0xFEFF, !units.contains(0) else { throw StrictJSONError(kind: .encoding, at: 0) }
        var reader = StrictJSON(units: units)
        let value = try reader.value(depth: 0)
        reader.skipSpace()
        guard reader.at == units.count else { throw reader.error(.syntax) }
        return value
    }

    func error(_ kind: StrictJSONError.Kind) -> StrictJSONError { StrictJSONError(kind: kind, at: at) }

    var peek: UInt16? { at < units.count ? units[at] : nil }

    mutating func skipSpace() {
        while let unit = peek, unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D { at += 1 }
    }

    mutating func expect(_ unit: UInt16) throws {
        guard peek == unit else { throw error(.syntax) }
        at += 1
    }

    /// `depth` counts the arrays and objects around this value.
    mutating func value(depth: Int) throws -> JSONValue {
        skipSpace()
        switch peek {
        case 0x7B?, 0x5B?:
            guard depth < Self.maxDepth else { throw error(.tooDeep) }
            return peek == 0x7B ? try object(depth: depth + 1) : try array(depth: depth + 1)
        case 0x22?: return .string(try string())
        case 0x74?: try literal("true"); return .bool(true)
        case 0x66?: try literal("false"); return .bool(false)
        case 0x6E?: try literal("null"); return .null
        default: return .number(try number())
        }
    }

    mutating func literal(_ word: String) throws {
        for unit in word.utf16 { try expect(unit) }
    }

    mutating func object(depth: Int) throws -> JSONValue {
        at += 1
        var members: [[UInt16]: JSONValue] = [:]
        skipSpace()
        if peek == 0x7D { at += 1; return .object(members) }
        while true {
            skipSpace()
            let start = at
            let key = try string()
            skipSpace()
            try expect(0x3A)
            guard members.updateValue(try value(depth: depth), forKey: key) == nil else {
                throw StrictJSONError(kind: .duplicateKey, at: start)
            }
            skipSpace()
            if peek == 0x2C { at += 1; continue }
            try expect(0x7D)
            return .object(members)
        }
    }

    mutating func array(depth: Int) throws -> JSONValue {
        at += 1
        var items: [JSONValue] = []
        skipSpace()
        if peek == 0x5D { at += 1; return .array(items) }
        while true {
            items.append(try value(depth: depth))
            skipSpace()
            if peek == 0x2C { at += 1; continue }
            try expect(0x5D)
            return .array(items)
        }
    }

    /// Units as written, escapes resolved one unit each: `\ud800` alone stays one unit.
    mutating func string() throws -> [UInt16] {
        try expect(0x22)
        var out: [UInt16] = []
        while let unit = peek, unit != 0x22 {
            guard unit >= 0x20 else { throw error(.syntax) }
            at += 1
            guard unit == 0x5C else { out.append(unit); continue }
            guard let escape = peek else { throw error(.syntax) }
            at += 1
            if let plain = Self.escapes[escape] { out.append(plain); continue }
            guard escape == 0x75, at + 4 <= units.count else { throw error(.syntax) }
            var code: UInt16 = 0
            for digit in units[at..<(at + 4)] {
                guard let value = Self.hex(digit) else { throw error(.syntax) }
                code = code << 4 | value
            }
            at += 4
            out.append(code)
        }
        try expect(0x22)
        return out
    }

    static func hex(_ unit: UInt16) -> UInt16? {
        switch unit {
        case 0x30...0x39: return unit - 0x30
        case 0x41...0x46: return unit - 0x37
        case 0x61...0x66: return unit - 0x57
        default: return nil
        }
    }

    /// RFC 8259: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, kept as its text.
    mutating func number() throws -> String {
        let start = at
        if peek == 0x2D { at += 1 }
        if peek == 0x30 { at += 1 } else { try digits() }
        if peek == 0x2E { at += 1; try digits() }
        guard peek == 0x65 || peek == 0x45 else { return String(decoding: units[start..<at], as: UTF16.self) }
        at += 1
        if peek == 0x2B || peek == 0x2D { at += 1 }
        try digits()
        return String(decoding: units[start..<at], as: UTF16.self)
    }

    mutating func digits() throws {
        let start = at
        while let unit = peek, (0x30...0x39).contains(unit) { at += 1 }
        guard at > start else { throw error(.syntax) }
    }
}
