import XCTest
@testable import DucturaCore

// Navigation policy for the shell's WKWebView (DAN-961): a listed host stays in the shell,
// another https host goes to the system browser, everything else is refused.
final class NavigationTests: XCTestCase {
    static let hosts = "ductura.org"

    func decide(_ url: String?, _ hosts: String? = hosts) -> NavigationDecision { Navigation.decide(url: url, hosts: hosts) }
    func scalars(_ s: String?) -> String { s.map { "\($0.unicodeScalars.map(\.value))" } ?? "nil" }

    func testOdbija() {
        let refused: [String?] = [
            nil, "", " ",
            "http://ductura.org/app/", "file:///etc/passwd", "file://ductura.org/x", "javascript:alert(1)",
            "JavaScript:alert(1)", "HTTPS://ductura.org/", "data:text/html,x", "blob:https://ductura.org/x",
            "about:blank", "ftp://ductura.org/", "ductura://doc/x", "wss://ductura.org/",
            "https://", "https:///x", "https:evil.com", "https:/evil.com", "//evil.com", "https:////evil.com",
            "https://ductura.org@evil.com/", "https://user@ductura.org/", "https://ductura.org:443/",
            "https://example.org:8443/", "https://ductura.org:/", "https://127.0.0.1/", "https://0x7f.1/",
            "https://[::1]/", "https://ductura.org./", "https://example.org./", "https://localhost/",
            "https://DUCTURA.org/", "https://ductura%2Eorg/", "https://ductura.org\\evil.com/",
            "https://toString/", "https://__proto__/", "https://" + String(repeating: "a", count: 64) + ".org/",
            "https://d\u{FA}ctura.org/", "https://ductura\u{3002}org/", "https://ductura.org/\u{FEFF}",
            "https://example.org/a|b", "https://example.org/{", "https://example.org/a\"b", "https://example.org/<",
            "https://example.org/^", "https://example.org/`",
        ]
        for url in refused { XCTAssertEqual(decide(url), .refuse, scalars(url)) }
    }

    func testOdbijaKontrolneIRazmakBiloGdje() {
        for c in ["\r\n", "\r", "\n", "\t", " ", "\u{A0}", "\u{7F}", "\u{0}"] {
            for url in ["\(c)https://ductura.org/", "https://ductura.org/\(c)", "https://ductura\(c).org/",
                        "https://exa\(c)mple.org/", "https://example.org/a\(c)b"] {
                XCTAssertEqual(decide(url), .refuse, scalars(url))
            }
        }
    }

    /// A bad or empty list refuses everything, the external host too (not `.browser`).
    func testLosPopisOdbijaSve() {
        for hosts in [nil, "", ";", "ductura.org;", "Ductura.org", "ductura.org;127.0.0.1", "ductura.org;__proto__"] {
            for url in ["https://ductura.org/", "https://example.org/"] {
                XCTAssertEqual(decide(url, hosts), .refuse, "\(hosts ?? "nil") \(url)")
            }
        }
    }

    func testHostSPopisaOstajeULjusci() {
        for url in ["https://ductura.org", "https://ductura.org/", "https://ductura.org/app/",
                    "https://ductura.org/app/#/doc/a%20b", "https://ductura.org/?x=1", "https://ductura.org/#x",
                    "https://ductura.org?x=1", "https://ductura.org#x", "https://ductura.org/../x"] {
            XCTAssertEqual(decide(url), .stay, url)
        }
        XCTAssertEqual(decide("https://app.test/", "ductura.org;app.test"), .stay)
    }

    func testDrugiHttpsHostIdeUPreglednik() {
        for url in ["https://example.org/", "https://example.org", "https://x.ductura.org/",
                    "https://ductura.org.evil.com/", "https://xn--dctura-ova.org/", "https://example.org/a?b=c#d"] {
            XCTAssertEqual(decide(url), .browser(url), url)
        }
    }
}
