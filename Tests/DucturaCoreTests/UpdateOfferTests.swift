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
        // 10 digits is valid for the server, but the client reads versions only through ClientVersion.parse (at most 9).
        assertRefused("version", [
            "1.0", "1.0.0.0", "01.0.0", "1.00.0", "1.0.0-beta", "1.0.0+1", "v1.0.0", "", "1.0.0\n", "\u{FF11}.0.0", "1234567890.0.0",
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
