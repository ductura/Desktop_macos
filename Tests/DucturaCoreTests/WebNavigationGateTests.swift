import Foundation
import XCTest
@testable import DucturaCore

// The web view's navigation delegate goes through the navigation rule (DAN-1544): a refused
// destination is never loaded, and only a link click opens another https host in the browser.
final class NavigationPolicyTests: XCTestCase {
    static let hosts = "ductura.org"
    static let frames: [NavigationFrame] = [.main, .sub, .newWindow]

    func policy(_ url: String?, _ frame: NavigationFrame, link: Bool = true, hosts: String? = hosts) -> NavigationPolicy {
        Navigation.policy(url: url, hosts: hosts, frame: frame, linkActivated: link)
    }

    /// Everything `Navigation.decide` refuses is cancelled in every frame, link click or not.
    func testOdbijenoSeNikadNeUcitava() {
        let refused: [String?] = [
            nil, "", "http://ductura.org/app/", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,x",
            "blob:https://ductura.org/x", "about:blank", "ductura://doc/x", "https://ductura.org:443/",
            "https://ductura.org@evil.com/", "https://127.0.0.1/", "https://DUCTURA.org/", "https://ductura.org/\u{FEFF}",
            "https://ductura.org/ x",
        ]
        for url in refused {
            XCTAssertEqual(Navigation.decide(url: url, hosts: Self.hosts), .refuse, url ?? "nil")
            for frame in Self.frames { for link in [true, false] {
                XCTAssertEqual(policy(url, frame, link: link), .cancel, "\(url ?? "nil") \(frame) \(link)")
            } }
        }
    }

    func testHostSPopisaUcitavaSeUOkviru() {
        for url in ["https://ductura.org/app/", "https://ductura.org/app/#/doc/a%20b", "https://ductura.org/api/v1/x?y=1"] {
            for link in [true, false] {
                XCTAssertEqual(policy(url, .main, link: link), .allow, url)
                XCTAssertEqual(policy(url, .sub, link: link), .allow, url)
                // The shell opens no new windows.
                XCTAssertEqual(policy(url, .newWindow, link: link), .cancel, url)
            }
        }
    }

    func testKlikNaDrugiHostIdeUPreglednik() {
        for url in ["https://example.org/", "https://x.ductura.org/a?b=c#d", "https://ductura.org.evil.com/"] {
            XCTAssertEqual(policy(url, .main), .cancelAndOpen(url), url)
            XCTAssertEqual(policy(url, .newWindow), .cancelAndOpen(url), url)
        }
    }

    /// Script, redirect, form or iframe towards another host: refused, the browser is not opened.
    func testDrugiHostBezKlikaIliUPodokviruSeOdbija() {
        let url = "https://example.org/"
        for frame in Self.frames { XCTAssertEqual(policy(url, frame, link: false), .cancel, "\(frame)") }
        XCTAssertEqual(policy(url, .sub, link: true), .cancel)
    }

    func testLosPopisHostovaOdbijaSve() {
        for hosts in [nil, "", ";", "Ductura.org", "ductura.org;127.0.0.1"] as [String?] {
            for url in ["https://ductura.org/app/", "https://example.org/"] {
                for frame in Self.frames {
                    XCTAssertEqual(policy(url, frame, hosts: hosts), .cancel, "\(hosts ?? "nil") \(url) \(frame)")
                }
            }
        }
    }
}

#if canImport(WebKit)
import WebKit

// The gate's own decision as WebKit's delegate method calls it: WebKit's WKNavigationAction and
// WKFrameInfo cannot be created outside WebKit, so the test passes the fields the method reads.
final class WebNavigationGateTests: XCTestCase {
    struct Outcome: Equatable {
        var policy: WKNavigationActionPolicy
        var opened: [URL] = []
        var mainFrames: [URL] = []
    }

    static let view = ObjectIdentifier(NSObject())

    func run(_ url: String?, _ frame: NavigationFrame, _ type: WKNavigationType = .linkActivated,
             hosts: String? = "ductura.org") -> Outcome {
        var opened: [URL] = [], mainFrames: [URL] = []
        let gate = WebNavigationGate(hosts: hosts, openExternally: { opened.append($0) },
                                     allowedMainFrame: { view, url in
                                         XCTAssertEqual(view, Self.view)
                                         mainFrames.append(url)
                                     })
        let isMainFrame: Bool? = switch frame { case .main: true; case .sub: false; case .newWindow: nil }
        let policy = gate.decide(url: url.flatMap(URL.init(string:)), isMainFrame: isMainFrame,
                                 navigationType: type, view: Self.view)
        return Outcome(policy: policy, opened: opened, mainFrames: mainFrames)
    }

    func testOdbijenoOdrediste() {
        for url in [nil, "http://ductura.org/app/", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,x",
                    "about:blank", "https://ductura.org:8443/", "https://127.0.0.1/", "https://ductura.org@evil.com/"] {
            for frame in [NavigationFrame.main, .sub, .newWindow] {
                XCTAssertEqual(run(url, frame), Outcome(policy: .cancel), "\(url ?? "nil") \(frame)")
            }
        }
    }

    func testDopustenoOdrediste() throws {
        let url = "https://ductura.org/app/#/doc/demo-1"
        let expected = try XCTUnwrap(URL(string: url))
        for type in [WKNavigationType.linkActivated, .other, .reload, .formSubmitted, .backForward] {
            XCTAssertEqual(run(url, .main, type), Outcome(policy: .allow, mainFrames: [expected]), "\(type.rawValue)")
            XCTAssertEqual(run(url, .sub, type), Outcome(policy: .allow), "\(type.rawValue)")
            XCTAssertEqual(run(url, .newWindow, type), Outcome(policy: .cancel), "\(type.rawValue)")
        }
    }

    func testKlikNaDrugiHostOtvaraPreglednik() throws {
        let url = "https://example.org/a?b=c"
        let expected = try XCTUnwrap(URL(string: url))
        XCTAssertEqual(run(url, .main), Outcome(policy: .cancel, opened: [expected]))
        XCTAssertEqual(run(url, .newWindow), Outcome(policy: .cancel, opened: [expected]))
    }

    /// Redirect or script (`.other`), form, reload, history or iframe towards another host.
    func testDrugiHostBezKlikaNeOtvaraNista() {
        let url = "https://example.org/"
        for type in [WKNavigationType.other, .formSubmitted, .formResubmitted, .reload, .backForward] {
            for frame in [NavigationFrame.main, .sub, .newWindow] {
                XCTAssertEqual(run(url, frame, type), Outcome(policy: .cancel), "\(type.rawValue) \(frame)")
            }
        }
        XCTAssertEqual(run(url, .sub, .linkActivated), Outcome(policy: .cancel))
    }

    func testLosPopisHostovaOdbijaSve() {
        for hosts in [nil, "", "Ductura.org"] as [String?] {
            for url in ["https://ductura.org/app/", "https://example.org/"] {
                XCTAssertEqual(run(url, .main, hosts: hosts), Outcome(policy: .cancel), "\(hosts ?? "nil") \(url)")
            }
        }
    }
}
#endif
