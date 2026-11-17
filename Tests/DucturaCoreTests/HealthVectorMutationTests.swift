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
        for (index, vector) in vectors.enumerated() {
            let changed = [
                HealthVector(name: vector.name + "-x", status: vector.status, body: vector.body),
                HealthVector(name: vector.name, status: vector.status == 200 ? 503 : 200, body: newer),
                HealthVector(name: vector.name, status: 200, body: newer),
            ]
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
}
