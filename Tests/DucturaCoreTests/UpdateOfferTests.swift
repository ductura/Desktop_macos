import XCTest
@testable import DucturaCore

// Offer of a newer package from the downloads.manifest.get body (DAN-1073, part 1073-1).
// Shape from ductura/server main cecf6c9, server/contracts/routes/downloads.ts. The locked
// test-fakes vectors of this route come in 1073-2. Every bad value is tried in the chosen
// row and in a windows row: the whole manifest is checked, never a partial list.
final class UpdateOfferTests: XCTestCase {
    static let shaArm = String(repeating: "a", count: 64)
    static let shaX64 = String(repeating: "b", count: 64)
    static let shaWin = String(repeating: "0123456789abcdef", count: 4)

    static func row(_ system: String, _ architecture: String, _ sha256: String, version: String = "1.0.0") -> [String: Any] {
        ["system": system, "architecture": architecture, "version": version,
         "url": "/preuzimanje/Ductura-\(system)-\(architecture).pkg", "sha256": sha256]
    }

    static let rows: [[String: Any]] = [
        row("windows", "x64", shaWin), row("macos", "arm64", shaArm), row("macos", "x64", shaX64),
    ]

    func offer(_ manifest: Any, _ architecture: UpdateArchitecture = .arm64, installed: String = "0.9.0") -> UpdateOffer? {
        let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.fragmentsAllowed])
        return UpdateOffer.offer(manifest: data, architecture: architecture, installed: installed)
    }

    /// The manifest with one field of row 0 (windows) or row 1 (macos/arm64) set or removed.
    func offerWith(row index: Int, _ field: String, _ value: Any?) -> UpdateOffer? {
        var rows = Self.rows
        rows[index][field] = value
        return offer(["packages": rows])
    }

    /// Each bad string and each non-string value (nil removes the key) refuses the manifest; the control does not.
    func assertRefused(_ field: String, _ strings: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(offer(["packages": Self.rows]), "control", file: file, line: line)
        for value in Self.notStrings + strings.map({ $0 as Any? }) {
            for index in [0, 1] {
                XCTAssertNil(offerWith(row: index, field, value), "\(field) \(String(describing: value)) in row \(index)", file: file, line: line)
            }
        }
    }

    static let notStrings: [Any?] = [nil, 1, 1.0, NSNull(), true, [] as [Any], ["a": "b"]]

    func testLosSha256NeDajePonudu() {
        let sha: String = Self.shaWin
        let tail = String(sha.dropFirst())
        let bad: [String] = [
            sha.uppercased(), "A" + tail, tail, sha + "a", "", tail + "g", " " + tail, sha + "\n", "\n" + tail,
            sha + "\u{A0}", sha + "\u{0}", "\u{FF41}" + tail, tail + "a\u{301}",
        ]
        assertRefused("sha256", bad)
    }

    func testNepoznataPlatformaIliArhitekturaNeDajePonudu() {
        assertRefused("system", ["linux", "MACOS", "macOS", "darwin", "Windows", "", "macos ", "macos\n"])
        assertRefused("architecture", ["aarch64", "ARM64", "x86", "amd64", "universal", "", "arm64\n"])
    }

    func testLosaVerzijaNeDajePonudu() {
        assertRefused("version", [
            "1.0", "1.0.0.0", "01.0.0", "1.00.0", "1.0.0-beta", "1.0.0+1", "v1.0.0", "", "1.0.0\n", "\u{FF11}.0.0", "-1.0.0",
        ])
    }

    func testLosUrlNeDajePonudu() {
        assertRefused("url", [
            "", "http://preuzimanje.example.invalid/a.pkg", "//preuzimanje.example.invalid/a.pkg", "preuzimanje/a.pkg",
            "/../a.pkg", "/preuzimanje/./a.pkg", "/preuzimanje/%2e%2e/a.pkg", "/a b.pkg", "/č.pkg", "/a.pkg#x", "/preuzimanje\\a.pkg",
            "/a.pkg\n", "https://a.localhost/a.pkg", "https://1.2.3.4/a.pkg", "https://preuzimanje.example.invalid",
            "https://PREUZIMANJE.example.invalid/a.pkg", "https://user@preuzimanje.example.invalid/a.pkg",
            "https://xn--a.example.invalid/a.pkg", "/" + String(repeating: "a", count: 2048),
        ])
        for url in ["https://preuzimanje.example.invalid/macos/a.pkg?v=1", "/" + String(repeating: "a", count: 2047)] {
            XCTAssertEqual(offerWith(row: 1, "url", url)?.url, url)
        }
    }

    func testPrazniINepoznatiKljuceviNeDajuPonudu() {
        for field in ["system", "architecture", "version", "url", "sha256"] {
            for index in [0, 1] { XCTAssertNil(offerWith(row: index, field, nil), "no \(field) in row \(index)") }
        }
        for key in ["", "extra", "Sha256"] {
            for index in [0, 1] { XCTAssertNil(offerWith(row: index, key, "x"), "key \(key) in row \(index)") }
            XCTAssertNil(offer(["packages": Self.rows, key: "x"]), "top key \(key)")
        }
        let bad: [Any] = [["pakages": Self.rows], [:] as [String: Any], ["packages": Self.rows[1]], ["packages": NSNull()],
                          ["packages": Self.rows + ["x"]], ["packages": Self.rows + [NSNull()]], Self.rows, "x", 1]
        for manifest in bad { XCTAssertNil(offer(manifest), "\(manifest)") }
        for text in ["", "{", "null", "{\"packages\":[]", "\u{FEFF}"] {
            XCTAssertNil(UpdateOffer.offer(manifest: Data(text.utf8), architecture: .arm64, installed: "0.9.0"), text)
        }
    }

    func testDvaRedaIstogParaNeDajuPonudu() {
        XCTAssertNil(offer(["packages": Self.rows + [Self.row("windows", "x64", Self.shaWin)]]))
        XCTAssertNil(offer(["packages": Self.rows + [Self.rows[1]]]))
        XCTAssertNil(offer(["packages": [Self.rows[1], Self.row("macos", "arm64", Self.shaArm, version: "0.1.0")]]))
        XCTAssertNil(offer(["packages": Self.rows + [Self.row("windows", "arm64", Self.shaWin), Self.rows[1]]]), "more than 4 rows")
    }

    // A key given twice: JSONSerialization keeps one value, so the raw text is counted too (review FAIL 1 on #15).
    func testDvaputNavedenKljucNeDajePonudu() {
        let bad = "\"sha256\":\"\(Self.shaArm.uppercased())\","
        let arm = "{\"system\":\"macos\",\"architecture\":\"arm64\",\"version\":\"1.0.0\",\"url\":\"/a.pkg\","
        let good = "\"sha256\":\"\(Self.shaArm)\"}"
        let cases = [
            "{\"packages\":[\(arm)\(good)]}",
            "{\"packages\":[\(arm)\(bad)\(good)]}",
            "{\"packages\":[\(arm)\(good.dropLast()),\(good)]}",
            "{\"packages\":[\(arm)\"sha\\u0032\\u00356\":\"x\",\(good)]}",
            "{\"packages\":[],\"packages\":[\(arm)\(good)]}",
            "{\"packages\" :[\(arm)\"url\"\t: \"/b.pkg\",\(good)]}",
        ]
        let spaced = " {\"packages\" :\n[ \(arm)\"sha256\"\r\n:\t\"\(Self.shaArm)\" } ] } "
        for control in [cases[0], spaced] {
            XCTAssertNotNil(UpdateOffer.offer(manifest: Data(control.utf8), architecture: .arm64, installed: "0.9.0"), control)
        }
        for text in cases.dropFirst() {
            XCTAssertNil(UpdateOffer.offer(manifest: Data(text.utf8), architecture: .arm64, installed: "0.9.0"), text)
        }
    }

    // JSONSerialization also reads text that is not JSON, such as a trailing comma (review FAIL on #15,
    // 85dfbf8). Each case is the control with one change that leaves it otherwise offerable,
    // so only the strict RFC 8259 check can refuse it.
    func testNestrogiJSONNeDajePonudu() {
        let row = "{\"system\":\"macos\",\"architecture\":\"arm64\",\"version\":\"1.0.0\",\"url\":\"/a.pkg\",\"sha256\":\"\(Self.shaArm)\"}"
        let win = "{\"system\":\"windows\",\"architecture\":\"x64\",\"version\":\"1.0.0\",\"url\":\"/b.pkg\",\"sha256\":\"\(Self.shaWin)\"}"
        let control = "{\"packages\":[\(win),\(row)]}"
        func offer(_ data: Data) -> UpdateOffer? { UpdateOffer.offer(manifest: data, architecture: .arm64, installed: "0.9.0") }
        let controls = [control, " \t\r\n\(control)\n", "{\"packag\\u0065s\":[\(win),\(row)]}", "{ \"packages\" : [ \(win) , \(row) ] }"]
        for text in controls { XCTAssertNotNil(offer(Data(text.utf8)), text) }
        let rowOpen = String(row.dropLast())
        let bad = [
            "{\"packages\":[\(win),\(row),]}",
            "{\"packages\":[\(win),\(row) , ]}",
            "{\"packages\":[\(win),\(rowOpen),}]}",
            "{\"packages\":[\(win),\(row)],}",
            "{\"packages\":[,\(win),\(row)]}",
            "{\"packages\":[\(win),,\(row)]}",
            "{\"packages\":[\(win) \(row)]}",
            "{,\"packages\":[\(win),\(row)]}",
            "{packages:[\(win),\(row)]}",
            "{'packages':[\(win),\(row)]}",
            "/* x */\(control)",
            "\(control)// x",
            "{\"packages\":[\(win),//x\n\(row)]}",
            "\(control),",
            "\(control) x",
            "\(control){}",
            "\(control)\u{0}",
            "\u{FEFF}\(control)",
            "\u{0C}\(control)",
            "\(control)\u{0B}",
            "{\"packages\":\u{A0}[\(win),\(row)]}",
            "{\"packages\":[\(win),\u{2028}\(row)]}",
            "{\"packages\":[\(win.replacingOccurrences(of: "/b.pkg", with: "/b\\x.pkg")),\(row)]}",
            "{\"packages\":[\(win.replacingOccurrences(of: "\"windows\"", with: "'windows'")),\(row)]}",
        ]
        for text in bad { XCTAssertNil(offer(Data(text.utf8)), text) }
        // Another encoding of the same text: JSONSerialization detects UTF-16 and UTF-32 (RFC 8259 §8.1: UTF-8 only).
        for encoding: String.Encoding in [.utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian, .utf32BigEndian] {
            XCTAssertNil(offer(control.data(using: encoding)!), "\(encoding)")
        }
        // Not UTF-8 inside a string of an extra member, which the count of members would refuse anyway,
        // so it is checked on the reader below.
        XCTAssertNil(offer(Data(control.utf8.dropLast()) + Data([0xFF, 0x7D])))
    }

    // The strict reader on its own: RFC 8259 grammar, one value per row; each bad text is a valid one with one change.
    func testStrogiCitacPoRFC8259() {
        func valid(_ bytes: [UInt8]) -> Bool { StrictJSON.isValid(Data(bytes)) }
        let good = [
            "{}", "[]", " [ ] ", "0", "-0", "1", "-12", "1.5", "0.0", "1e5", "1E+5", "1e-5", "-1.25E10", "\"\"", "\"a\"",
            "true", "false", "null", "[1,2,3]", "{\"a\":1,\"b\":[true,false,null]}", "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"",
            "\"\\u0041\\u00e9\"", "\"\\uD83D\\uDE00\"", "\"\\ud83d\\ude00\"", "\"č😀\"", "{\"a\":{\"a\":{}}}",
            String(repeating: "[", count: StrictJSON.maxDepth) + String(repeating: "]", count: StrictJSON.maxDepth),
            String(repeating: "{\"a\":", count: StrictJSON.maxDepth) + "1" + String(repeating: "}", count: StrictJSON.maxDepth),
        ]
        for text in good { XCTAssertTrue(valid(Array(text.utf8)), text) }
        let bad = [
            "", " ", "[1,]", "[,1]", "[1,,2]", "[1 2]", "{\"a\":1,}", "{,\"a\":1}", "{\"a\" 1}", "{\"a\":}", "{a:1}",
            "{'a':1}", "{\"a\":1 \"b\":2}", "[1]]", "[[1]", "{}}", "{1:1}", "{null:1}",
            "01", "-", "-a", "+1", ".5", "1.", "1.e5", "1e", "1e+", "0x10", "NaN", "Infinity", "-Infinity", "1_0", "١",
            "tru", "True", "nul", "NULL", "falsey", "undefined",
            "'a'", "\"a", "\"\\x\"", "\"\\'\"", "\"\\u12\"", "\"\\u12g4\"", "\"\\U0041\"", "\"\\\"",
            "\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0041\"", "\"\\uD800x\"", "\"\\uDE00\\uD83D\"",
            "\"\t\"", "\"\n\"", "\"\u{0}\"", "\"\u{1F}\"",
            "/**/1", "1//", "# x\n1", "1 2", "[] []", "1\u{0}", "\u{FEFF}1", "\u{0C}1", "1\u{0B}", "\u{A0}1", "\u{3000}1",
            String(repeating: "[", count: StrictJSON.maxDepth + 1) + String(repeating: "]", count: StrictJSON.maxDepth + 1),
            String(repeating: "{\"a\":", count: StrictJSON.maxDepth + 1) + "1" + String(repeating: "}", count: StrictJSON.maxDepth + 1),
        ]
        for text in bad { XCTAssertFalse(valid(Array(text.utf8)), text.debugDescription) }
        // Not well-formed UTF-8 inside a string (RFC 3629): stray, overlong, surrogate, above U+10FFFF, cut short.
        let badUTF8: [[UInt8]] = [[0x80], [0xBF], [0xC0, 0x80], [0xC1, 0xBF], [0xE0, 0x80, 0x80], [0xE0, 0x9F, 0xBF],
                                  [0xED, 0xA0, 0x80], [0xED, 0xBF, 0xBF], [0xF0, 0x80, 0x80, 0x80], [0xF0, 0x8F, 0xBF, 0xBF],
                                  [0xF4, 0x90, 0x80, 0x80], [0xF5, 0x80, 0x80, 0x80], [0xFF], [0xFE], [0xC3], [0xE2, 0x82],
                                  [0xF0, 0x9F, 0x98], [0xC3, 0x41], [0xE2, 0x41, 0xAC], [0xF0, 0x9F, 0x41, 0x80], [0xF0, 0x9F, 0x98, 0x41]]
        let goodUTF8: [[UInt8]] = [[0xC2, 0x80], [0xDF, 0xBF], [0xE0, 0xA0, 0x80], [0xED, 0x9F, 0xBF], [0xEE, 0x80, 0x80],
                                   [0xF0, 0x90, 0x80, 0x80], [0xF4, 0x8F, 0xBF, 0xBF], [0x7F]]
        for bytes in goodUTF8 { XCTAssertTrue(valid([0x22] + bytes + [0x22]), "\(bytes)") }
        for bytes in badUTF8 { XCTAssertFalse(valid([0x22] + bytes + [0x22]), "\(bytes)") }
        // Cut short at the end of the data, with no closing quote.
        for bytes in [[0xC3], [0xE2, 0x82], [0xF0, 0x9F, 0x98]] as [[UInt8]] { XCTAssertFalse(valid([0x22] + bytes), "\(bytes)") }
        // The same text in UTF-16 or UTF-32 is not UTF-8.
        for encoding: String.Encoding in [.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            XCTAssertFalse(StrictJSON.isValid("{\"a\":1}".data(using: encoding)!), "\(encoding)")
        }
    }

    // Any number of digits is valid in the contract, so the comparison never goes through Int (review FAIL 2 on #15).
    func testDugaVerzijaPoUgovoru() {
        let long = "123456789012345678901234567890"
        for (offered, installed) in [("1234567890.0.0", "0.9.0"), ("\(long).0.0", "\(long.dropLast()).9.9"), ("1.0.\(long)", "1.0.9")] {
            XCTAssertEqual(offer(["packages": [Self.row("macos", "arm64", Self.shaArm, version: offered)]], installed: installed)?.version, offered)
            XCTAssertNil(offer(["packages": [Self.row("macos", "arm64", Self.shaArm, version: installed)]], installed: offered))
            XCTAssertNil(offer(["packages": [Self.row("macos", "arm64", Self.shaArm, version: offered)]], installed: offered))
        }
    }

    func testJednakaIliStarijaVerzijaNeDajePonudu() {
        // A malformed installed version offers nothing, even where a lenient reading ("0.9" as 0.9.0) would be older.
        for installed in ["1.0.0", "1.0.1", "1.1.0", "2.0.0", "__VERSION__", "1.0", "", " 0.9.0", "0.9", "00.9.0", "+0.9.0"] {
            XCTAssertNil(offer(["packages": Self.rows], installed: installed), installed)
        }
        XCTAssertEqual(offer(["packages": [Self.row("macos", "arm64", Self.shaArm, version: "1.10.0")]], installed: "1.9.0")?.version, "1.10.0")
        XCTAssertEqual(offer(["packages": Self.rows], installed: "0.9.9")?.version, "1.0.0")
    }

    func testNovijaVerzijaNudiRedSvojeArhitekture() {
        XCTAssertEqual(offer(["packages": Self.rows], .arm64), UpdateOffer(
            version: "1.0.0", url: "/preuzimanje/Ductura-macos-arm64.pkg", sha256: Self.shaArm, architecture: .arm64))
        XCTAssertEqual(offer(["packages": Self.rows], .x64), UpdateOffer(
            version: "1.0.0", url: "/preuzimanje/Ductura-macos-x64.pkg", sha256: Self.shaX64, architecture: .x64))
        XCTAssertNil(offer(["packages": [Self.rows[0]]], .x64), "windows is never offered")
        XCTAssertNil(offer(["packages": [Self.rows[1]]], .x64), "no row for x64")
        XCTAssertNil(offer(["packages": [] as [Any]]))
    }
}
