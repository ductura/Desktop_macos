import Foundation
import XCTest
@testable import DucturaCore

// The web address comes from package configuration (DAN-883, part 883-2);
// the cases follow ductura/desktop-windows WebAddressTests (fb045c0f).
final class WebAddressTests: XCTestCase {
    static let hosts = "ductura.org"

    func ok(_ url: String?, _ hosts: String? = hosts) -> Bool { WebAddress.make(url: url, hosts: hosts) != nil }

    func testOdbijaAdresu() {
        let bad: [String?] = [
            nil, "", " ",
            "http://ductura.org/app/", "file:///C:/app/", "javascript:alert(1)", "ftp://ductura.org/app/",
            "ws://ductura.org/app/", "wss://ductura.org/app/", "/app/", "ductura.org/app/", "C:\\app\\", "\\\\server\\share\\",
            "https://evil.org/app/", "https://x.ductura.org/app/", "https://ductura.org.evil.com/app/",
            "https://ductura.org./app/", "https://127.0.0.1/app/", "https://0x7f.1/app/", "https://[::1]/app/",
            "https://user@ductura.org/app/", "https://ductura.org@evil.com/app/", "https://toString/app/",
            "https://__proto__/app/", "https://ductura.org",
            "HTTPS://ductura.org/app/", "https://DUCTURA.org/app/", "https://ductura.org:443/app/",
            "https://ductura.org:8443/app/", "https://ductura.org:/app/", "https://ductura.org\\app\\",
            "https://ductura.org/a/../app/", "https://ductura.org/./app/", "https://ductura.org/%2e%2e/app/",
            "https://ductura.org//app/", "https://ductura.org/app//", "https://ductura.org/app/?", "https://ductura.org/app/?x=1",
            "https://ductura.org/app/#", "https://ductura.org/app/#/doc/x", "https://ductura.org/app",
            " https://ductura.org/app/", "https://ductura.org/app/ ", "https://ductura.org/app/\r",
            "https://ductura.org/app/\n", "https://ductura.org/app/\r\n", "https://ductura.org/app/\t",
            "https://ductura.org/a\tpp/", "https://ductura.org/a\u{7F}pp/", "https://ductura.org/a\u{A0}pp/",
            "\u{A0}https://ductura.org/app/", "https://ductura.org/app/\u{0}", "https://d\u{FA}ctura.org/app/",
            "https://ductura.org\u{3002}org/app/", "https://ductura.org/app\u{FEFF}/",
        ]
        for url in bad { XCTAssertFalse(ok(url), url.map { "\($0.unicodeScalars.map(\.value))" } ?? "nil") }
    }

    func testOdbijaPrazanPopisIliPrazanUnos() {
        for hosts in [nil, "", ";", "ductura.org;", ";ductura.org", "a.test;;ductura.org"] {
            XCTAssertFalse(ok("https://ductura.org/app/", hosts), hosts ?? "nil")
        }
    }

    /// One bad entry next to the right host refuses the whole list (fail closed).
    func testOdbijaPopisSNeispravnimUnosom() {
        for entry in ["Ductura.org", " ductura.org", "ductura.org ", "ductura .org", "ductura.org.", ".ductura.org",
                      "ductura..org", "ductura.org:443", "127.0.0.1", "-ductura.org", "ductura-.org", "*.ductura.org",
                      "ductura.org\r\n", "ductura.org\t", "ductura.org\u{A0}", "ductura.org\u{7F}", "toString", "__proto__",
                      "d\u{FA}ctura.org", String(repeating: "a", count: 64) + ".org"] {
            XCTAssertFalse(ok("https://ductura.org/app/", "ductura.org;" + entry), entry)
        }
    }

    func testIPINeASCIIHostNiKadJeNaPopisu() {
        for (url, hosts) in [("https://127.0.0.1/app/", "127.0.0.1"), ("https://0x7f.1/app/", "0x7f.1"),
                             ("https://[::1]/app/", "[::1]"), ("https://d\u{FA}ctura.org/app/", "d\u{FA}ctura.org")] {
            XCTAssertFalse(ok(url, hosts), url)
        }
    }

    func testPrihvacaIspravnuAdresuSPopisa() {
        for (url, hosts) in [("https://ductura.org/app/", "ductura.org"), ("https://ductura.org/", "ductura.org"),
                             ("https://ductura.org/app/", "a.test;ductura.org"), ("https://a.test/app/", "a.test;ductura.org"),
                             ("https://web-1.a.test/x/y~z_1.0/", "web-1.a.test")] {
            XCTAssertEqual(WebAddress.make(url: url, hosts: hosts)?.url, url)
        }
    }

    func testFromInfo() {
        let good: [String: Any] = [WebAddress.urlKey: "https://ductura.org/app/", WebAddress.hostsKey: "ductura.org"]
        XCTAssertEqual(WebAddress.fromInfo(good)?.url, "https://ductura.org/app/")
        XCTAssertNil(WebAddress.fromInfo(nil))
        XCTAssertNil(WebAddress.fromInfo([:]))
        XCTAssertNil(WebAddress.fromInfo([WebAddress.urlKey: "https://ductura.org/app/"]))
        XCTAssertNil(WebAddress.fromInfo([WebAddress.urlKey: ["https://ductura.org/app/"], WebAddress.hostsKey: "ductura.org"]))
        XCTAssertNil(WebAddress.fromInfo([WebAddress.urlKey: "https://ductura.org/app/", WebAddress.hostsKey: ["ductura.org"]]))
        XCTAssertNil(WebAddress.fromInfo([WebAddress.urlKey: "http://ductura.org/app/", WebAddress.hostsKey: "ductura.org"]))
    }

    /// The shipped packaging/Info.plist (the bundle's configuration) gives https and the /app/ path.
    func testIsporucenaKonfiguracijaDajePutApp() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("packaging/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
        let web = try XCTUnwrap(WebAddress.fromInfo(info))
        XCTAssertEqual(URL(string: web.url)?.scheme, "https")
        XCTAssertTrue(web.url.hasSuffix("/app/"))
        XCTAssertEqual(Startup.smoke(web: web, version: "0.1.0").exitCode, 0)
    }
}

// What the app does with the package address; main.swift only applies these results.
final class StartupTests: XCTestCase {
    static let web = WebAddress.make(url: "https://ductura.org/app/", hosts: "ductura.org")

    func testNeispravnaAdresaDajeIzlaz1BezPotvrdeIBezPoveznice() {
        for url in ["http://ductura.org/app/", "https://evil.org/app/", ""] {
            let web = WebAddress.make(url: url, hosts: "ductura.org")
            XCTAssertNil(web, url)
            XCTAssertEqual(Startup.smoke(web: web, version: "0.1.0").exitCode, 1)
            XCTAssertNil(Startup.smoke(web: web, version: "0.1.0").line)
            XCTAssertNil(Startup.linkURL(options: LaunchOptions.parse(["ductura://doc/demo-1"]), web: web))
        }
        XCTAssertEqual(Startup.invalidAddressText, "Adresa Ducture u ovom paketu nije ispravna.")
    }

    func testIspravnaAdresaDajePotvrduIPoveznicuNaRad() {
        XCTAssertEqual(Startup.smoke(web: Self.web, version: "0.1.0").exitCode, 0)
        XCTAssertEqual(Startup.smoke(web: Self.web, version: "0.1.0").line, "Ductura OK 0.1.0")
        XCTAssertEqual(Startup.linkURL(options: LaunchOptions.parse(["ductura://doc/demo-1"]), web: Self.web)?.absoluteString,
                       "https://ductura.org/app/#/doc/demo-1")
        XCTAssertEqual(Startup.linkURL(options: LaunchOptions.parse([]), web: Self.web)?.absoluteString, "https://ductura.org/app/")
        XCTAssertEqual(Startup.linkURL(options: LaunchOptions.parse(["ductura://doc/%00"]), web: Self.web)?.absoluteString,
                       "https://ductura.org/app/")
    }
}
