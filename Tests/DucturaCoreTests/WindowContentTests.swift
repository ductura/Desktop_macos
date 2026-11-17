import Foundation
import XCTest
@testable import DucturaCore

// Window content of the shell (DAN-957): a WKWebView only for a checked address.
final class WindowContentTests: XCTestCase {
    static let web = WebAddress.make(url: "https://ductura.org/app/", hosts: "ductura.org")

    func testNeispravnaAdresaOstajePoruka() {
        let message = WindowContent.message(Startup.invalidAddressText)
        for url in ["http://ductura.org/app/", "https://evil.org/app/", "file:///app/", "javascript:alert(1)", ""] {
            let web = WebAddress.make(url: url, hosts: "ductura.org")
            XCTAssertEqual(Startup.windowContent(options: LaunchOptions(), web: web), message, url)
            XCTAssertEqual(Startup.windowContent(options: LaunchOptions(openDocumentId: "demo-1"), web: web), message, url)
        }
    }

    func testIzvjestajBezJednogWebViewaNijeWeb() {
        let url = URL(string: "https://ductura.org/app/")
        let text = Startup.invalidAddressText
        XCTAssertEqual(Startup.windowReport(webViews: [], messages: [text]), "Ductura window message")
        for (views, messages) in [([], []), ([url], [text]), ([url, url], []), ([nil], []), ([], ["drugo"]), ([], [text, text])] as [([URL?], [String])] {
            XCTAssertEqual(Startup.windowReport(webViews: views, messages: messages), "Ductura window error", "\(views) \(messages)")
        }
    }

    func testIspravnaAdresaUWebView() throws {
        let web = try XCTUnwrap(Self.web)
        XCTAssertEqual(Startup.windowContent(options: LaunchOptions(), web: web),
                       .web(URL(string: "https://ductura.org/app/")!))
    }

    func testRadSKodiranimIdom() throws {
        let web = try XCTUnwrap(Self.web)
        XCTAssertEqual(Startup.windowContent(options: LaunchOptions(openDocumentId: "a b"), web: web),
                       .web(URL(string: "https://ductura.org/app/#/doc/a%20b")!))
        // An invalid id falls back to the address itself, as linkURL does.
        XCTAssertEqual(Startup.windowContent(options: LaunchOptions(openDocumentId: " x"), web: web),
                       .web(URL(string: "https://ductura.org/app/")!))
    }

    func testIzvjestajWebViewa() {
        XCTAssertEqual(Startup.windowReport(webViews: [URL(string: "https://ductura.org/app/")], messages: []),
                       "Ductura window web https://ductura.org/app/")
    }
}
