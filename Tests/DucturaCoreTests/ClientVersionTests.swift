import XCTest
@testable import DucturaCore

// Launch check against health.minClientVersion (DAN-945): no network, only the decision.
final class ClientVersionTests: XCTestCase {
    func decide(_ client: String, _ minimum: String?, status: String = "ok") -> ClientVersionDecision {
        ClientVersion.decide(.answered(status: status, minClientVersion: minimum), clientVersion: client)
    }

    static let malformed = [
        "", "__VERSION__", "1.0", "1", "01.0.0", "1.00.0", "1.0.0-beta", "1.0.0+1", " 1.0.0", "1.0.0 ", "1.0.0\n", "1.0.0\r\n",
        "1.0.0\t", "1.0.0\u{A0}", "1.0.0\u{7F}", "\u{FF11}.0.0", "\u{0661}.0.0", "+1.0.0", "-1.0.0", "v1.0.0",
        "99999999999999999999.0.0", "1..2", "1.2.3.4", "1.0.0.", ".1.0.0", "1.0.0\u{0}",
    ]

    func testStarijiKlijentTraziNadogradnju() {
        for (client, minimum) in [("0.9.9", "1.0.0"), ("1.2.3", "1.2.10"), ("1.9.0", "1.10.0"), ("0.0.0", "0.0.1"), ("1.10.9", "2.0.0")] {
            XCTAssertEqual(decide(client, minimum), .updateRequired(minimum: minimum), "\(client) < \(minimum)")
        }
    }

    func testNeispravnaVerzijaKlijentaUzMinimumTraziNadogradnju() {
        for client in Self.malformed {
            XCTAssertEqual(decide(client, "0.0.0"), .updateRequired(minimum: "0.0.0"), "\(client.unicodeScalars.map(\.value))")
        }
    }

    func testNedostupanIliNeispravanServer() {
        XCTAssertEqual(ClientVersion.decide(.unavailable, clientVersion: "1.0.0"), .serverUnavailable)
        for status in ["down", "", "OK", "ok ", "degraded"] {
            XCTAssertEqual(decide("1.0.0", "9.0.0", status: status), .serverUnavailable, status)
            XCTAssertEqual(decide("1.0.0", "1.0", status: status), .serverUnavailable, status)
        }
        for minimum in Self.malformed {
            XCTAssertEqual(decide("1.0.0", minimum), .serverUnavailable, "\(minimum.unicodeScalars.map(\.value))")
        }
    }

    func testIstiNovijiIliBezMinimumaOtvara() {
        for (client, minimum) in [("1.0.0", "1.0.0"), ("1.0.1", "1.0.0"), ("1.10.0", "1.9.0"), ("2.0.0", "1.99.99"), ("0.1.0", "0.0.0")] {
            XCTAssertEqual(decide(client, minimum), .open, "\(client) >= \(minimum)")
        }
        XCTAssertEqual(decide("1.0.0", nil), .open)
        XCTAssertEqual(decide("__VERSION__", nil), .open)
    }

    func testWebSeNeOtvaraZaNadogradnju() {
        let link = URL(string: "https://ductura.org/app/")!
        XCTAssertNil(ClientVersion.webURL(.updateRequired(minimum: "9.0.0"), link: link))
        XCTAssertNil(ClientVersion.webURL(.updateRequired(minimum: "9.0.0"), link: nil))
        XCTAssertEqual(ClientVersion.webURL(.open, link: link), link)
        XCTAssertEqual(ClientVersion.webURL(.serverUnavailable, link: link), link)
        XCTAssertNil(ClientVersion.webURL(.open, link: nil))
    }

    func testPorukaJeStaticnaIHrvatska() {
        XCTAssertTrue(ClientVersion.updateText.contains("nadogradi"))
        XCTAssertFalse(ClientVersion.updateText.contains("http"))
        XCTAssertFalse(ClientVersion.updateText.contains("9.0.0"))
    }
}
