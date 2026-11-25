import Foundation
import XCTest
@testable import DucturaCore

// Launch health call and client version header (DAN-1545): fake transport, no network.
final class HealthProbeTests: XCTestCase {
    static let web = WebAddress.make(url: "https://ductura.org/app/", hosts: "ductura.org")!

    func response(_ status: Int = 200, type: String? = "application/json") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://ductura.org/api/v1/health")!, statusCode: status, httpVersion: nil,
                        headerFields: type.map { ["Content-Type": $0] })!
    }

    func testZahtjevNosiVerzijuKlijentaNaApiPutu() throws {
        let request = try XCTUnwrap(HealthProbe.request(web: Self.web, clientVersion: "1.2.3"))
        XCTAssertEqual(request.url?.absoluteString, "https://ductura.org/api/v1/health")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: ClientVersionHeader.headerName), "1.2.3")
        XCTAssertEqual(request.timeoutInterval, HealthProbe.timeout)
    }

    func testNeispravnaVerzijaNeDajeZaglavlje() throws {
        for bad in ClientVersionTests.malformed {
            let request = try XCTUnwrap(HealthProbe.request(web: Self.web, clientVersion: bad))
            XCTAssertNil(request.value(forHTTPHeaderField: ClientVersionHeader.headerName), "\(bad.unicodeScalars.map(\.value))")
        }
    }

    func testZaglavljeSamoNaApiPutuIstogPodrijetla() {
        let h = { (url: String?) in ClientVersionHeader.headers(version: "1.0.0", url: url, web: Self.web) }
        XCTAssertEqual(h("https://ductura.org/api/v1/health"), [ClientVersionHeader.headerName: "1.0.0"])
        for url in [nil, "https://ductura.org/app/", "https://evil.org/api/v1/health", "http://ductura.org/api/v1/health",
                    "https://ductura.org/api/v1/../x", "https://ductura.org.evil.org/api/v1/x"] {
            XCTAssertEqual(h(url), [:], url ?? "nil")
        }
        XCTAssertEqual(ClientVersionHeader.headers(version: "1.0.0", url: "https://ductura.org/api/v1/health", web: nil), [:])
    }

    func testOdgovorSeBrojiSamoPoUgovoru() {
        let ok = Data(#"{"status":"ok","minClientVersion":"1.0.0"}"#.utf8)
        XCTAssertEqual(HealthProbe.reading(data: ok, response: response()), .answered(status: "ok", minClientVersion: "1.0.0"))
        XCTAssertEqual(HealthProbe.reading(data: Data(#"{"status":"ok","minClientVersion":null}"#.utf8), response: response()),
                       .answered(status: "ok", minClientVersion: nil))
        XCTAssertEqual(HealthProbe.reading(data: ok, response: response(500)), .unavailable)
        XCTAssertEqual(HealthProbe.reading(data: ok, response: response(204)), .unavailable)
        XCTAssertEqual(HealthProbe.reading(data: ok, response: response(type: "text/html")), .unavailable)
        XCTAssertEqual(HealthProbe.reading(data: ok, response: response(type: nil)), .unavailable)
        XCTAssertEqual(HealthProbe.reading(data: ok, response: nil), .unavailable)
        for body in ["", "<html>", "[]", #"{"status":1}"#, #"{"status":"ok","minClientVersion":3}"#, #"{"minClientVersion":"1.0.0"}"#] {
            XCTAssertEqual(HealthProbe.reading(data: Data(body.utf8), response: response()), .unavailable, body)
        }
    }

    func testPoziviProlazeKrozPrijenos() async {
        var seen: URLRequest?
        let reading = await HealthProbe.read(web: Self.web, clientVersion: "0.1.0") { request in
            seen = request
            return (Data(#"{"status":"ok","minClientVersion":"1.0.0"}"#.utf8), self.response())
        }
        XCTAssertEqual(seen?.value(forHTTPHeaderField: ClientVersionHeader.headerName), "0.1.0")
        XCTAssertEqual(ClientVersion.decide(reading, clientVersion: "0.1.0"), .updateRequired(minimum: "1.0.0"))
        XCTAssertEqual(ClientVersion.decide(reading, clientVersion: "1.0.0"), .open)
    }

    func testGreskaPrijenosaJeNedostupanServer() async {
        struct Down: Error {}
        let reading = await HealthProbe.read(web: Self.web, clientVersion: "1.0.0") { _ in throw Down() }
        XCTAssertEqual(reading, .unavailable)
        XCTAssertEqual(ClientVersion.decide(reading, clientVersion: "1.0.0"), .serverUnavailable)
    }

    func testProzorPoOdluciOVerziji() {
        let options = LaunchOptions()
        XCTAssertEqual(Startup.windowContent(options: options, web: Self.web, decision: .open), .web(URL(string: "https://ductura.org/app/")!))
        XCTAssertEqual(Startup.windowContent(options: options, web: Self.web, decision: .serverUnavailable), .web(URL(string: "https://ductura.org/app/")!))
        XCTAssertEqual(Startup.windowContent(options: options, web: Self.web, decision: .updateRequired(minimum: "9.0.0")), .message(ClientVersion.updateText))
        XCTAssertEqual(Startup.windowContent(options: options, web: nil, decision: .open), .message(Startup.invalidAddressText))
        XCTAssertEqual(Startup.windowContent(options: options, web: nil, decision: .updateRequired(minimum: "9.0.0")), .message(Startup.invalidAddressText))
        XCTAssertEqual(Startup.windowReport(webViews: [], messages: [ClientVersion.updateText]), "Ductura window message")
    }
}
