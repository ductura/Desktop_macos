import Foundation
import XCTest
@testable import DucturaCore

final class UpdateOfferTests: XCTestCase {
    private let armURL = "https://preuzimanje.example.invalid/m-arm64.dmg"
    private let x64URL = "/preuzimanje/m-x64.dmg"
    private let armSHA = String(repeating: "a", count: 64)
    private let x64SHA = String(repeating: "b", count: 64)

    private var macRows: [String] {
        [row(arch: "arm64", url: armURL, sha: armSHA), row(url: x64URL, sha: x64SHA)]
    }

    private var windowsRows: [String] {
        [row(system: "windows", arch: "arm64", url: "/preuzimanje/w-arm64.msi"),
         row(system: "windows", url: "/preuzimanje/w-x64.msi")]
    }

    private func row(
        system: String = "macos", arch: String = "x64", version: String = "1.0.0",
        url: String = "/preuzimanje/paket.dmg", sha: String = String(repeating: "d", count: 64)
    ) -> String {
        #"{"system":"\#(system)","architecture":"\#(arch)","version":"\#(version)","url":"\#(url)","sha256":"\#(sha)"}"#
    }

    private func manifest(_ rows: [String]) -> String {
        #"{"packages":[\#(rows.joined(separator: ","))]}"#
    }

    private func decide(
        _ body: String?, installed: String? = "0.9.0", arch: UpdateArchitecture = .x64, status: Int = 200
    ) -> UpdateOffer? {
        UpdateOffer.decide(status: status, body: body.map { Data($0.utf8) }, installedVersion: installed, architecture: arch)
    }

    func testNudiSamoNovijiMacOSRedakZaTrazenuArhitekturu() {
        let rows = macRows + windowsRows
        for (arch, url, sha) in [(UpdateArchitecture.arm64, armURL, armSHA), (.x64, x64URL, x64SHA)] {
            for order in [rows, Array(rows.reversed())] {
                let body = manifest(order)
                XCTAssertEqual(decide(body, arch: arch), UpdateOffer(version: "1.0.0", url: url, sha256: sha))
                XCTAssertNil(decide(body, installed: "1.0.0", arch: arch))
                XCTAssertNil(decide(body, installed: "1.0.1", arch: arch))
            }
        }
        for (missing, present, index) in [(UpdateArchitecture.x64, UpdateArchitecture.arm64, 0), (.arm64, .x64, 1)] {
            let body = manifest([macRows[index]] + windowsRows)
            XCTAssertNotNil(decide(body, arch: present))
            XCTAssertNil(decide(body, arch: missing))
        }
        XCTAssertNil(decide(manifest([])))
    }

    func testAdresaOstajeDoslovna() {
        let urls = [
            "/preuzimanje/paket.dmg", "/preuzimanje/paket.dmg?v=1.0.0&kanal=stabilni",
            "/preuzimanje/%7Eductura/%41%2f.dmg?x=%2F&y=a+b", "/preuzimanje/a;b=c/(d)!$'*,:@~.dmg/",
            "https://preuzimanje.example.invalid/a//b/c.dmg?", "https://dl.example.invalid/%7Eductura/%41.dmg?x=%2F",
            "/" + String(repeating: "a", count: 2047),
        ]
        for arch in UpdateArchitecture.allCases {
            for url in urls {
                XCTAssertEqual(decide(manifest([row(arch: arch.rawValue, url: url)]), arch: arch)?.url, url)
            }
            let escapedURL = #"\/preuzimanje\/paket\u002edmg?x=1\u0026y=2"#
            XCTAssertEqual(decide(manifest([row(arch: arch.rawValue, url: escapedURL)]), arch: arch)?.url, "/preuzimanje/paket.dmg?x=1&y=2")
        }
    }

    private func assertInvalidRows(_ invalidRows: [String], file: StaticString = #filePath, line: UInt = #line) {
        for invalid in invalidRows {
            for arch in UpdateArchitecture.allCases {
                for rows in [macRows + [invalid], [invalid] + macRows] {
                    XCTAssertNil(decide(manifest(rows), arch: arch), invalid, file: file, line: line)
                }
            }
        }
    }

    func testNeispravnaAdresaURetkuDrugogSustavaOdbijaManifest() {
        let longLabel = String(repeating: "a", count: 64)
        let longHost = Array(repeating: String(repeating: "a", count: 60), count: 4).joined(separator: ".") + ".example.invalid"
        let badURLs = [
            "", "/" + String(repeating: "a", count: 2048),
            #"/p\n"#, #"/p\r\n"#, #"/p\t"#, #"/p\u00a0"#, #"/p\u007f"#, #"/p\ud800"#,
            #"\\\\server\\share\\a.msi"#, #"C:\\Ductura\\a.msi"#, #"/preuzimanje/a\\b.msi"#,
            "http://dl.example.invalid/a.msi", "//dl.example.invalid/a.msi", "https://dl.localhost/a.msi",
            "https://dl.local/a.msi", "https://dl.internal/a.msi", "https://dl.home.arpa/a.msi",
            "https://Dl.example.invalid/a.msi", "https://dl.example.invalid:443/a.msi", "https://dl.example.invalid/a.msi#x",
            "/p/../a.msi", "/p/%2e%2e/a.msi", "/p/a%00.msi", "/p/a%2Eb.msi",
            "/p/./a.msi", "/p/.", "/p/..", "/p/..?v=1", "/p/.?v=1", "/?v=1",
            "https://dl.example.invalid//a.msi", "https://dl.example.invalid/?v=1",
            "https://xn--dl-0ka.example.invalid/a.msi", "https://dl.xn--p1ai/a.msi", "https://dl.xn--d1a.example.invalid/a.msi",
            "https://1.2.3.4/a.msi", "https://dl_x.example.invalid/a.msi", "https://-dl.example.invalid/a.msi",
            "https://dl.example.invalid./a.msi", "https://\(longLabel).example.invalid/a.msi", "https://\(longHost)/a.msi",
            "/p/a b.msi", "/p/a%zz.msi", "/p/a%0.msi", "/p/a<b>.msi",
        ]
        assertInvalidRows(badURLs.map { row(system: "windows", url: $0) })
    }

    func testNeispravnaVerzijaIliSHAURetkuDrugogSustavaOdbijaManifest() {
        let sha = String(repeating: "d", count: 64)
        let badHashes = [String(sha.dropLast()), sha + "d", " " + sha, armSHA.uppercased()]
            + [#"\n"#, #"\r\n"#, #"\t"#, #"\u00a0"#, #"\u007f"#].map { sha + $0 }
            + [#"\u0661"#, "D", "g"].map { String(sha.dropLast()) + $0 }
        assertInvalidRows(badHashes.map { row(system: "windows", sha: $0) })
        let badVersions = ["", "1.0", "01.0.0", "1.0.0.0", " 1.0.0", "0.١.0", "1.0.0-rc.1", "1.0.0+1"]
            + [#"\n"#, #"\r\n"#, #"\t"#, #"\u00a0"#, #"\u007f"#].map { "1.0.0" + $0 }
        assertInvalidRows(badVersions.map { row(system: "windows", version: $0) })
    }

    func testNeispravniKljuceviTipoviIVrijednostiOdbijajuManifest() {
        let windows = windowsRows[1]
        let sha = String(repeating: "d", count: 64)
        let mutations = [
            row(system: "Windows"), row(system: "linux", arch: "arm64"),
            row(system: "windows", arch: "ia32"), row(arch: "ia32"),
            windows.replacingOccurrences(of: #","sha256":"\#(sha)""#, with: ""),
            windows.replacingOccurrences(of: #""sha256":"\#(sha)""#, with: #""sha256":null"#),
            windows.replacingOccurrences(of: #""version":"1.0.0""#, with: #""version":1"#),
            windows.replacingOccurrences(of: "sha256", with: "Sha256"),
            windows.replacingOccurrences(of: "sha256", with: #"sha\ud800256"#),
            "1", "null",
        ]
        let appended = [#""extra":"x""#, #""__proto__":"x""#, #""toString":"x""#, #""sha256":"\#(sha)""#,
                        #""sha\u003256":"\#(sha)""#].map { "\(windows.dropLast()),\($0)}" }
        assertInvalidRows(mutations + appended)
        let valid = manifest(macRows)
        let badRoots = [#"{"packages":null}"#, #"{"packages":{}}"#, #"{"packages":[],\#(valid.dropFirst())"#,
                        #"{"package\u0073":[],\#(valid.dropFirst())"#, #"{"extra":1,\#(valid.dropFirst())"#,
                        #"{"__proto__":{},\#(valid.dropFirst())"#, #"\#(valid.dropLast()),"toString":1}"#,
                        "\u{feff}" + valid, valid + " false", "\(valid.dropLast()),}"]
        for root in badRoots { XCTAssertNil(decide(root), root) }
    }

    func testDupliParZaBiloKojiSustavOdbijaManifest() {
        for (rows, duplicate) in [(macRows, row()), (macRows + [windowsRows[1]], row(system: "windows"))] {
            for arch in UpdateArchitecture.allCases {
                XCTAssertNil(decide(manifest(rows + [duplicate]), arch: arch))
                XCTAssertNil(decide(manifest([duplicate] + rows), arch: arch))
            }
        }
    }

    func testNeispravanStatusTijeloIliInstaliranaVerzijaNeNudePaket() {
        let valid = manifest(macRows)
        for status in [204, 503] { XCTAssertNil(decide(valid, status: status)) }
        for body in [nil, "", "not json", "[]", "{}", #"{"packages":[1]}"#] as [String?] {
            XCTAssertNil(decide(body))
        }
        for installed in [nil, "", "1.0", " 0.9.0", "0.9.0\n", "0.9.0\r\n", "0.9.0\t", "0.9.0\u{a0}",
                          "0.9.0\u{7f}", "0.9.0.0", "00.9.0", "٠.9.0", "0.9.0-beta"] as [String?] {
            XCTAssertNil(decide(valid, installed: installed))
        }
        for arch in ["", "X64", "x64 ", "ia32"] { XCTAssertNil(UpdateArchitecture(rawValue: arch)) }
        let invalidUTF8: [[UInt8]] = [[0xED, 0xA0, 0x80], [0xED, 0xB0, 0x80, 0xED, 0xA0, 0x80]]
        for bytes in invalidUTF8 {
            let body = Data(valid.utf8) + Data(bytes)
            XCTAssertNil(UpdateOffer.decide(status: 200, body: body, installedVersion: "0.9.0", architecture: .x64))
        }
    }

    func testVerzijeUsporedujeBrojcanoBezOgranicenjaVelicine() {
        let cases = [
            ("99999999999.0.0", "0.9.0", true), ("1.0.99999999999", "1.0.0", true),
            ("1.99999999999.0", "1.9.99999999999", true), ("100000000000.0.0", "99999999999.0.0", true),
            ("1234567890123456789012345678901234567890.0.0", "1234567890123456789012345678901234567889.9.9", true),
            ("1.10.0", "1.9.0", true), ("1.0.10", "1.0.9", true), ("10.0.0", "9.99.99", true),
            ("99999999999.0.0", "99999999999.0.0", false), ("1.0.0", "99999999999.0.0", false),
            ("1.0.0", "1.0.99999999999", false), ("99999999999.0.0", "100000000000.0.0", false),
            ("1.9.0", "1.10.0", false),
        ]
        for (offered, installed, newer) in cases {
            for arch in UpdateArchitecture.allCases {
                let target = row(arch: arch.rawValue, version: offered)
                let other = row(system: "windows", version: offered)
                for rows in [[target, other], [other, target]] {
                    XCTAssertEqual(decide(manifest(rows), installed: installed, arch: arch)?.version, newer ? offered : nil)
                }
            }
        }
    }
}
