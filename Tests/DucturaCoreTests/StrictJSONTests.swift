import XCTest
@testable import DucturaCore

// Strict RFC 8259 reader with the I-JSON limits (DAN-1073, part 1073-2a): negatives first, each next to a passing control.
final class StrictJSONTests: XCTestCase {
    func ok(_ text: String) -> Bool { StrictJSON.parse(Data(text.utf8)) != nil }
    func ok(bytes: [UInt8]) -> Bool { StrictJSON.parse(Data(bytes)) != nil }
    func show(_ text: String) -> String { "\(text.unicodeScalars.map(\.value))" }

    func testPonovljenKljucVracaNil() {
        for text in [
            #"{"sha256":"x","sha256":"0f"}"#, #"{"a":1,"a":1}"#, #"{"a":1,"\u0061":1}"#, #"{"\u00e9":1,"e\u0301":1}"#,
            "{\"\u{E9}\":1,\"\\u00E9\":1}", #"{"a/":1,"a\/":1}"#, #"{"":1,"":2}"#, #"{"x":{"b":1,"b":2}}"#,
            #"[{"a":1},{"b":1,"b":1}]"#, #"{"__proto__":1,"__proto__":1}"#, #"{"toString":1,"toString":2}"#,
        ] { XCTAssertFalse(ok(text), text) }
        for text in [#"[{"a":1},{"a":1}]"#, #"{"a":1,"a\u0000":1}"#, #"{"a":{"a":1}}"#, #"{"__proto__":1,"toString":1}"#] {
            XCTAssertTrue(ok(text), text)
        }
    }

    func testNestrogiJSONVracaNil() {
        for text in [
            "[1,]", "[,1]", "[1,,2]", #"{"a":1,}"#, #"{,"a":1}"#, "[1 2]", #"{"a" 1}"#, #"{"a":1 "b":2}"#, "[1]//x", "/*x*/[1]",
            "{a:1}", #"{a":1}"#, #"{'a":1}"#, "['a']", "NaN", "Infinity", "-Infinity", "True", "tru", "nul", "truex", "nulll", "trUe", "nulL", "falsy", "[trux]", "[1]]", "{}{}", "1 2",
            "", " ", "\n", "[", "{", #"{"a"}"#, #"{"a":}"#, "[1}", #"{"a":1]"#, "\"x",
        ] { XCTAssertFalse(ok(text), show(text)) }
        for text in ["\"x\"", "1", "true", "false", "null", "[]", "{}", "{ \"a\" :\r\n[ 1 ,\t2 ] }", " [ ] ", "\r{}\r"] {
            XCTAssertTrue(ok(text), show(text))
        }
    }

    func testRazmakIzvanRFCVracaNil() {
        for space in ["\u{A0}", "\u{C}", "\u{B}", "\u{2028}", "\u{7F}", "\u{0}", "\u{FEFF}"] {
            XCTAssertFalse(ok("[1\(space)]"), show(space))
            XCTAssertFalse(ok("\(space){}"), show(space))
        }
        for space in [" ", "\t", "\n", "\r", "\r\n"] { XCTAssertTrue(ok("[1\(space),\(space)2]\(space)"), show(space)) }
    }

    func testNizoviZnakova() {
        for code in 0...0x1F { XCTAssertFalse(ok("[\"a\(Character(Unicode.Scalar(UInt8(code))))\"]"), "\(code)") }
        for text in [
            #"["\x"]"#, #"["\'"]"#, #"["\u00G0"]"#, #"["\u12"]"#, #"["\uD800"]"#, #"["\uDC00"]"#, #"["\uDBFF\u0041"]"#,
            #"["\uD800\uD800"]"#, #"["\"]"#, #"["\U00e9"]"#,
        ] { XCTAssertFalse(ok(text), text) }
        for code: UInt32 in [0xFDD0, 0xFDEF, 0xFFFE, 0xFFFF, 0x1FFFE, 0x1FFFF, 0x10FFFE, 0x10FFFF] {
            let raw = String(Unicode.Scalar(code)!)
            let escaped = String(raw.utf16.map { String(format: "\\u%04X", $0) }.joined())
            for text in ["[\"\(raw)\"]", "{\"\(raw)\":1}", "[\"\(escaped)\"]", "{\"a\(escaped)\":1}"] { XCTAssertFalse(ok(text), show(text)) }
        }
        for code: UInt32 in [0xFDCF, 0xFDF0, 0xFFFD, 0x1FFFD, 0x10000] { XCTAssertTrue(ok("[\"\(Unicode.Scalar(code)!)\"]"), "\(code)") }
        for text in [#"["\uD83D\uDE00"]"#, #"["\u0000"]"#, #"["\/"]"#, #"["\u00e9\u00E9"]"#, "[\"\u{7F}\"]", "[\"\u{2028}\"]", #"["\"\\\b\f\n\r\t"]"#] {
            XCTAssertTrue(ok(text), text)
        }
        XCTAssertEqual(StrictJSON.parse(Data(#"["\uD83D\uDE00\/\u00e9"]"#.utf8)), .array([.string("😀/é")]))
    }

    func testKodiranje() {
        let control: [UInt8] = Array("[\"a\"]".utf8)
        for bytes: [UInt8] in [
            [0xEF, 0xBB, 0xBF] + control, [0x20, 0xEF, 0xBB, 0xBF] + control, [0xFF, 0xFE, 0x5B, 0x00, 0x5D, 0x00],
            [0x00, 0x5B, 0x00, 0x5D], [0x22, 0xC0, 0xAF, 0x22], [0x22, 0xED, 0xA0, 0x80, 0x22], [0x22, 0xF4, 0x90, 0x80, 0x80, 0x22],
            [0x22, 0xC3, 0x22], [0x22, 0xF0, 0x9F, 0x98], [0x22, 0x80, 0x22], [0x22, 0xF5, 0x80, 0x80, 0x80, 0x22], [0x22, 0xFF, 0x22],
        ] { XCTAssertFalse(ok(bytes: bytes), "\(bytes)") }
        XCTAssertTrue(ok(bytes: control))
        XCTAssertEqual(StrictJSON.parse(Data("{\"čćžšđ\":\"😀\"}".utf8)), .object(["čćžšđ": .string("😀")]))
    }

    func testBrojevi() {
        for text in ["01", "00", "-", "+1", "1.", ".5", "1e", "1e+-5", "0x10", "-01", "- 1", "1.e5", "--1", "1e5.0"] {
            XCTAssertFalse(ok(text), text)
            XCTAssertFalse(ok("[\(text)]"), text)
        }
        let long = String(repeating: "9", count: 400)
        for text in ["0", "-0", "1.5e+10", "1E-5", "1e05", "1e999999", "0.0", long] {
            XCTAssertEqual(StrictJSON.parse(Data("[\(text)]".utf8)), .array([.number(text)]), text)
        }
    }

    func testDubina() {
        func nested(_ open: String, _ close: String, _ n: Int) -> String {
            String(repeating: open, count: n) + "1" + String(repeating: close, count: n)
        }
        XCTAssertTrue(ok(nested("[", "]", 32)))
        XCTAssertTrue(ok(nested(#"{"a":"#, "}", 32)))
        XCTAssertTrue(ok(nested(#"[{"a":"#, "}]", 16)))
        XCTAssertFalse(ok(nested("[", "]", 33)))
        XCTAssertFalse(ok(nested(#"{"a":"#, "}", 33)))
        XCTAssertFalse(ok(nested("[", "]", 10_000)))
        XCTAssertFalse(ok(String(repeating: "[", count: 10_000)))
    }

    func testIspravanJSONDajeStablo() {
        let text = #"{"packages":[{"system":"macos","architecture":"arm64","version":"1.0.0","url":"https://x.test/a.dmg","n":-0.5e1,"b":[true,false,null]}]}"#
        let row: [String: JSONValue] = [
            "system": .string("macos"), "architecture": .string("arm64"), "version": .string("1.0.0"),
            "url": .string("https://x.test/a.dmg"), "n": .number("-0.5e1"), "b": .array([.bool(true), .bool(false), .null]),
        ]
        XCTAssertEqual(StrictJSON.parse(Data(text.utf8)), .object(["packages": .array([.object(row)])]))
    }
}
