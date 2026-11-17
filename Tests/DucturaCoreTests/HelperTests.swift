import XCTest
@testable import DucturaCore

final class LaunchOptionsTests: XCTestCase {
    func testPrazniArgumenti() {
        XCTAssertEqual(LaunchOptions.parse([]), LaunchOptions())
    }
    func testSmokeOut() {
        let o = LaunchOptions.parse(["--smoke-out", "/tmp/ok.txt"])
        XCTAssertTrue(o.smoke)
        XCTAssertEqual(o.smokeOutput, "/tmp/ok.txt")
    }
    func testSmokeWindowBezPutanjeSeIgnorira() {
        XCTAssertEqual(LaunchOptions.parse(["--smoke-window"]), LaunchOptions())
        XCTAssertEqual(LaunchOptions.parse(["--smoke-window", ""]), LaunchOptions())
        XCTAssertEqual(LaunchOptions.parse(["--smoke-window", "--smoke"]), LaunchOptions(smoke: true))
        XCTAssertEqual(LaunchOptions.parse(["--smoke-window", "DUCTURA://doc/a"]), LaunchOptions(openDocumentId: "a"))
    }
    func testSmokeWindowGradiProzor() {
        // The window must really be built, so --smoke-window does not turn on --smoke.
        let o = LaunchOptions.parse(["--smoke-window", "/tmp/w.txt"])
        XCTAssertFalse(o.smoke)
        XCTAssertNil(o.smokeOutput)
        XCTAssertEqual(o.smokeWindowOutput, "/tmp/w.txt")
    }
    func testPoveznicaOtvaraDokument() {
        XCTAssertEqual(LaunchOptions.parse(["ductura://doc/demo-1"]).openDocumentId, "demo-1")
        XCTAssertEqual(LaunchOptions.parse(["ductura://doc/demo-1/"]).openDocumentId, "demo-1")
        XCTAssertNil(LaunchOptions.parse(["ductura://doc/"]).openDocumentId)
    }
}

final class PackagingTests: XCTestCase {
    func testNazivPaketaOdgovaraPreloaderu() {
        XCTAssertEqual(Packaging.dmgFileName, "Ductura-macOS.dmg")
    }
    func testPutanjaUAplikacijama() {
        XCTAssertEqual(Packaging.installedAppPath(), "/Applications/Ductura.app")
    }
    func testUsporedbaVerzija() {
        XCTAssertTrue(Packaging.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(Packaging.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(Packaging.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(Packaging.isNewer("0.1.0", than: "0.2.0"))
        XCTAssertFalse(Packaging.isNewer("x", than: "0.1.0"))
    }
}
