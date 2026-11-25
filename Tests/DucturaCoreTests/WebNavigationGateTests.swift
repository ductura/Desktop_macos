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

final class FakeFrameInfo: WKFrameInfo {
    let main: Bool
    init(main: Bool) { self.main = main; super.init() }
    override var isMainFrame: Bool { main }
}

final class FakeNavigationAction: WKNavigationAction {
    let fakeRequest: URLRequest
    let fakeFrame: WKFrameInfo?
    let fakeType: WKNavigationType
    init(url: URL?, frame: NavigationFrame, type: WKNavigationType) {
        var request = URLRequest(url: URL(string: "https://placeholder.invalid/")!)
        request.url = url
        fakeRequest = request
        switch frame {
        case .main: fakeFrame = FakeFrameInfo(main: true)
        case .sub: fakeFrame = FakeFrameInfo(main: false)
        case .newWindow: fakeFrame = nil
        }
        fakeType = type
        super.init()
    }
    override var request: URLRequest { fakeRequest }
    override var targetFrame: WKFrameInfo? { fakeFrame }
    override var navigationType: WKNavigationType { fakeType }
}

final class WebNavigationGateTests: XCTestCase {
    struct Outcome: Equatable {
        var policies: [WKNavigationActionPolicy] = []
        var opened: [URL] = []
        var mainFrames: [URL] = []
    }

    func run(_ url: String?, _ frame: NavigationFrame, _ type: WKNavigationType = .linkActivated,
             hosts: String? = "ductura.org") -> Outcome {
        var outcome = Outcome()
        let gate = WebNavigationGate(hosts: hosts, openExternally: { outcome.opened.append($0) },
                                     allowedMainFrame: { _, url in outcome.mainFrames.append(url) })
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let action = FakeNavigationAction(url: url.flatMap(URL.init(string:)), frame: frame, type: type)
        gate.webView(webView, decidePolicyFor: action) { outcome.policies.append($0) }
        return outcome
    }

    func testOdbijenoOdrediste() {
        for url in [nil, "http://ductura.org/app/", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,x",
                    "about:blank", "https://ductura.org:8443/", "https://127.0.0.1/", "https://ductura.org@evil.com/"] {
            for frame in [NavigationFrame.main, .sub, .newWindow] {
                XCTAssertEqual(run(url, frame), Outcome(policies: [.cancel]), "\(url ?? "nil") \(frame)")
            }
        }
    }

    func testDopustenoOdrediste() throws {
        let url = "https://ductura.org/app/#/doc/demo-1"
        let expected = try XCTUnwrap(URL(string: url))
        for type in [WKNavigationType.linkActivated, .other, .reload, .formSubmitted, .backForward] {
            XCTAssertEqual(run(url, .main, type), Outcome(policies: [.allow], mainFrames: [expected]), "\(type.rawValue)")
            XCTAssertEqual(run(url, .sub, type), Outcome(policies: [.allow]), "\(type.rawValue)")
            XCTAssertEqual(run(url, .newWindow, type), Outcome(policies: [.cancel]), "\(type.rawValue)")
        }
    }

    func testKlikNaDrugiHostOtvaraPreglednik() throws {
        let url = "https://example.org/a?b=c"
        let expected = try XCTUnwrap(URL(string: url))
        XCTAssertEqual(run(url, .main), Outcome(policies: [.cancel], opened: [expected]))
        XCTAssertEqual(run(url, .newWindow), Outcome(policies: [.cancel], opened: [expected]))
    }

    /// Redirect or script (`.other`), form, reload, history or iframe towards another host.
    func testDrugiHostBezKlikaNeOtvaraNista() {
        let url = "https://example.org/"
        for type in [WKNavigationType.other, .formSubmitted, .formResubmitted, .reload, .backForward] {
            for frame in [NavigationFrame.main, .sub, .newWindow] {
                XCTAssertEqual(run(url, frame, type), Outcome(policies: [.cancel]), "\(type.rawValue) \(frame)")
            }
        }
        XCTAssertEqual(run(url, .sub, .linkActivated), Outcome(policies: [.cancel]))
    }

    func testLosPopisHostovaOdbijaSve() {
        for hosts in [nil, "", "Ductura.org"] as [String?] {
            for url in ["https://ductura.org/app/", "https://example.org/"] {
                XCTAssertEqual(run(url, .main, hosts: hosts), Outcome(policies: [.cancel]), "\(hosts ?? "nil") \(url)")
            }
        }
    }

    /// The delegate the shell installs is the gate, not a policy that allows everything.
    func testWebViewKoristiGate() {
        let gate = WebNavigationGate(hosts: "ductura.org", openExternally: { _ in })
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = gate
        XCTAssertTrue(webView.navigationDelegate === gate)
    }
}
#endif
