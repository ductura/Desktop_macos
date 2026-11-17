import Foundation
import XCTest
@testable import DucturaCore

// DAN-999 follow-up (DAN-1001): each real health vector of the locked @ductura/test-fakes, changed one
// at a time, makes the same check as testSvakiHealthVektorDajeOcekivaniIshod fail.
final class HealthVectorMutationTests: XCTestCase {
    func testPromijenjenPraviHealthVektorRusiProvjeru() throws {
        let vectors = try TestFakesRelease.release.get()
        XCTAssertNoThrow(try TestFakesRelease.check(vectors))
        let newer = Data(#"{"status":"ok","minClientVersion":"9.0.0"}"#.utf8)
        // Thresholds that both table clients (1.0.0, 0.9.9) still pass; 0.9.9 would refuse a 0.9.8 client.
        let lower = ["0.0.0", "0.9.9"].map { Data(#"{"status":"ok","minClientVersion":"\#($0)"}"#.utf8) }
        for (index, vector) in vectors.enumerated() {
            let changed = [
                HealthVector(name: vector.name + "-x", status: vector.status, body: vector.body),
                HealthVector(name: vector.name, status: vector.status == 200 ? 503 : 200, body: newer),
                HealthVector(name: vector.name, status: 200, body: newer),
            ] + lower.map { HealthVector(name: vector.name, status: 200, body: $0) }
            for change in changed {
                var list = vectors
                list[index] = change
                XCTAssertThrowsError(try TestFakesRelease.check(list), "\(vector.name) → \(change.name) \(change.status)") { error in
                    let text = "\(error)"
                    XCTAssertTrue(text.hasPrefix("vektor \(vector.name):") || text.hasPrefix("health vektori "), text)
                }
            }
        }
    }

    /// Offline (review c.6959287300): a threshold both table clients pass still changes the reading.
    func testPragKojiKlijentiIzTabliceProlazeRusiProvjeru() {
        func vector(_ name: String, _ status: Int, _ body: String) -> HealthVector { HealthVector(name: name, status: status, body: Data(body.utf8)) }
        let current = #"{"status":"ok","state":"ok","minClientVersion":"1.0.0"}"#
        let valid = [vector("alive", 200, #"{"status":"ok"}"#), vector("alive-with-version", 200, #"{"status":"ok","version":"1.2.0"}"#),
                     vector("alive-current", 200, current), vector("degraded", 200, current), vector("internal", 500, "{}"), vector("too-many-requests", 429, "{}")]
        XCTAssertNoThrow(try TestFakesRelease.check(valid))
        for minimum in ["0.0.0", "0.9.9"] {
            let changed = [vector("alive", 200, #"{"status":"ok","minClientVersion":"\#(minimum)"}"#)] + valid.dropFirst()
            XCTAssertEqual(changed.map { ClientVersion.decide(TestFakesRelease.reading($0), clientVersion: "1.0.0") }.first, .open)
            XCTAssertThrowsError(try TestFakesRelease.check(changed), minimum) { XCTAssertTrue("\($0)".hasPrefix("vektor alive:"), "\($0)") }
        }
    }
}
