import XCTest
@testable import DucturaCore

// Generated contract client (DAN-959): the health response decodes tolerantly and the request
// joins the base address with the contract path.
final class ContractsTests: XCTestCase {
    func decode(_ json: String) throws -> PlatformHealthGetResponse {
        try JSONDecoder().decode(PlatformHealthGetResponse.self, from: Data(json.utf8))
    }

    func testBezStatusaNeDekodira() {
        for json in [#"{}"#, #"{"status":null}"#, #"{"status":1}"#, #"{"state":"ok"}"#, #"[]"#, ""] {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testDekodiraSvaPolja() throws {
        let r = try decode(#"{"status":"ok","version":"1.18.0","state":"degraded","apiVersion":"1.18.0","serverVersion":"0.3.1","minClientVersion":"0.2.0"}"#)
        XCTAssertEqual(r.status, "ok")
        XCTAssertEqual(r.state, "degraded")
        XCTAssertEqual(r.minClientVersion, "0.2.0")
        XCTAssertEqual(r.serverVersion, "0.3.1")
    }

    func testTolerantanNaNovaPoljaIVrijednosti() throws {
        let only = try decode(#"{"status":"ok"}"#)
        XCTAssertNil(only.minClientVersion)
        XCTAssertNil(only.state)
        XCTAssertEqual(try decode(#"{"status":"ok","state":"maintenance","newField":{"a":1}}"#).state, "maintenance")
        XCTAssertNil(try decode(#"{"status":"ok","minClientVersion":null}"#).minClientVersion)
    }

    func testZahtjevHealth() {
        XCTAssertEqual(PlatformHealthGet.method, "GET")
        let cases = [
            ("https://api.ductura.org", "https://api.ductura.org/api/v1/health"),
            ("https://api.ductura.org/", "https://api.ductura.org/api/v1/health"),
            ("https://ductura.org/server/", "https://ductura.org/server/api/v1/health"),
            ("https://ductura.org/server", "https://ductura.org/server/api/v1/health"),
        ]
        for (base, want) in cases {
            let request = PlatformHealthGet.request(base: URL(string: base)!)
            XCTAssertEqual(request.url?.absoluteString, want, base)
            XCTAssertEqual(request.httpMethod, "GET", base)
        }
    }
}
