import Foundation
import XCTest

// DAN-1008-1: the strict JSON reader for contract vectors. Every refused input must throw a
// StrictJSONError of the expected kind (never another error, never a crash). Negative cases first.
final class StrictJSONTests: XCTestCase {
    func kind(_ bytes: [UInt8]) -> StrictJSONError.Kind? {
        do { _ = try StrictJSON.parse(Data(bytes)); return nil } catch { return (error as? StrictJSONError)?.kind }
    }

    func kind(_ text: String) -> StrictJSONError.Kind? { kind(Array(text.utf8)) }

    func u(_ text: String) -> [UInt16] { Array(text.utf16) }

    static let encoding: [[UInt8]] = [
        [0x22, 0xC0, 0x80, 0x22], [0x22, 0x80, 0x22], [0x22, 0xED, 0xA0, 0x80, 0x22], [0x22, 0xF4, 0x90, 0x80, 0x80, 0x22],
        [0x22, 0xFF, 0x22], [0x22, 0xC4, 0x22], [0xEF, 0xBB, 0xBF, 0x7B, 0x7D],
        Array(#"{"a":1}"#.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }, // UTF-16LE without BOM
        Array(#"{"a":1}"#.utf16).flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }, // UTF-16BE without BOM
        Array("\"a\u{0}b\"".utf8), Array("{}\u{0}".utf8), Array("\u{0}{}".utf8),
    ]

    static let syntax: [String] = [
        // whitespace outside strings: only SP, TAB, LF and CR
        "\u{A0}{}", "{}\u{2028}", "\u{0B}1", "\u{0C}1", "[1,\u{FEFF}2]", "\u{85}[]",
        // strings
        "\"a\tb\"", "\"a\nb\"", "\"a\rb\"", "\"\u{1}\"", "\"\u{1F}\"", #""\x""#, #""\U0041""#, #""\u12""#,
        #""\u12G4""#, #""\u""#, "\"abc", "'a'", #""\""#, #"{"a\":1}"#,
        // numbers
        "01", "-01", "-", "1.", ".5", "+1", "1e", "1e+", "1.e5", "0x1", "NaN", "Infinity", "-Infinity", "[01]", "1 2",
        // structure
        "[1,]", #"{"a":1,}"#, #"{"a" 1}"#, #"{"a"}"#, "{1:2}", "[1 2]", "{} {}", "{}x", "", " \r\n\t", "[", "{", "]", "[}",
        // literals
        "True", "nul", "truex", "nulll", "[tru]", "FALSE",
    ]

    static let duplicateKey: [String] = [
        #"{"a":1,"a":2}"#, #"{"a":1,"a":1}"#, #"{"\ud800":1,"\uD800":2}"#, #"{"x":{"b":1,"b":1}}"#,
        #"[{"a":1,"a":1}]"#, #"{"😀":1,"😀":2}"#, #"{"__proto__":1,"__proto__":2}"#,
    ]

    static func nested(_ depth: Int) -> String { String(repeating: "[", count: depth) + String(repeating: "]", count: depth) }

    func testNeispravanUlazDajeGreskuTocneVrste() {
        for bytes in Self.encoding { XCTAssertEqual(kind(bytes), .encoding, "\(bytes)") }
        for text in Self.syntax { XCTAssertEqual(kind(text), .syntax, text.debugDescription) }
        for text in Self.duplicateKey { XCTAssertEqual(kind(text), .duplicateKey, text) }
    }

    func testDubokoUgnijezdenUlazDajeGreskuNePad() {
        XCTAssertEqual(kind(Self.nested(StrictJSON.maxDepth + 1)), .tooDeep)
        XCTAssertEqual(kind(String(repeating: "[", count: 100_000)), .tooDeep)
        XCTAssertEqual(kind(String(repeating: #"{"a":"#, count: 100_000)), .tooDeep)
        XCTAssertNil(kind(Self.nested(StrictJSON.maxDepth)))
    }

    func testIspravanUlazDajeTocnuVrijednost() throws {
        let long = "9" + String(repeating: "0", count: 399)
        let cases: [(String, JSONValue)] = [
            (" \t\r\n{\"a\" : [ 1 , -0 , 1.5e300 , 1E-2, 0 ] }\r\n",
             .object([u("a"): .array([.number("1"), .number("-0"), .number("1.5e300"), .number("1E-2"), .number("0")])])),
            ("1.0000000000000001", .number("1.0000000000000001")), (long, .number(long)),
            ("true", .bool(true)), ("false", .bool(false)), ("null", .null), ("[]", .array([])), ("{}", .object([:])),
            ("\"\u{7F}\u{A0}č\"", .string([0x7F, 0xA0, 0x10D])),
            (#""𐀀x\udc00""#, .string([0xD800, 0xDC00, 0x78, 0xDC00])),
            (#""😀""#, .string(u("😀"))), ("\"😀\"", .string(u("😀"))),
            (#""\"\\\/\b\f\n\r\téé""#, .string([0x22, 0x5C, 0x2F, 0x08, 0x0C, 0x0A, 0x0D, 0x09, 0xE9, 0xE9])),
            (#"{"\ud800":1,"__proto__":null,"toString":true,"constructor":[]}"#,
             .object([[0xD800]: .number("1"), u("__proto__"): .null, u("toString"): .bool(true), u("constructor"): .array([])])),
            (#"[{"a":1},{"a":2}]"#, .array([.object([u("a"): .number("1")]), .object([u("a"): .number("2")])])),
            (#"{"input":0,"accepted":false}"#, .object([u("input"): .number("0"), u("accepted"): .bool(false)])),
        ]
        for (text, value) in cases { XCTAssertEqual(try StrictJSON.parse(Data(text.utf8)), value, text) }
    }

    func testSvakaVrstaGreskeImaTekst() {
        let kinds: [StrictJSONError.Kind] = [.encoding, .syntax, .duplicateKey, .tooDeep]
        let texts = kinds.map { StrictJSONError(kind: $0, at: 3).description }
        XCTAssertEqual(Set(texts).count, kinds.count)
        for text in texts { XCTAssertTrue(text.hasPrefix("JSON ") && text.hasSuffix(", UTF-16 jedinica 3"), text) }
    }
}
