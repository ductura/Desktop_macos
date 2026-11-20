import XCTest
@testable import DucturaCore

// Invented tokens only.
final class AuthHeaderTests: XCTestCase {
    func testValidTokenGivesBearer() {
        XCTAssertEqual(AuthHeader.value(token: "izmisljeni-token_1.2~3+4/5=="), "Bearer izmisljeni-token_1.2~3+4/5==")
    }

    func testInvalidTokensGiveNoHeader() {
        let bad: [String?] = [nil, "", " ", "a b", "a\r\nX: 1", "a\nb", "a\u{0}b", "\"a\"", "tok;en", "tokén", "😀",
                              String(repeating: "a", count: AuthHeader.maxLength + 1)]
        for t in bad { XCTAssertNil(AuthHeader.value(token: t), "\(String(describing: t))") }
        XCTAssertNotNil(AuthHeader.value(token: String(repeating: "a", count: AuthHeader.maxLength)))
    }

    func testTokenReadFromEnvironmentOnly() {
        XCTAssertEqual(AuthHeader.token(environment: [AuthHeader.environmentKey: "abc"]), "abc")
        XCTAssertNil(AuthHeader.token(environment: [:]))
    }

    func testHeaderOnlyForAllowedHosts() {
        let hosts = "ductura.test"
        XCTAssertEqual(AuthHeader.headers(token: "abc", url: "https://ductura.test/app/", hosts: hosts),
                       ["Authorization": "Bearer abc"])
        XCTAssertTrue(AuthHeader.headers(token: "abc", url: "https://drugi.test/app/", hosts: hosts).isEmpty)
        XCTAssertTrue(AuthHeader.headers(token: "abc", url: "http://ductura.test/app/", hosts: hosts).isEmpty)
        XCTAssertTrue(AuthHeader.headers(token: "a b", url: "https://ductura.test/app/", hosts: hosts).isEmpty)
        XCTAssertTrue(AuthHeader.headers(token: nil, url: "https://ductura.test/app/", hosts: hosts).isEmpty)
        XCTAssertTrue(AuthHeader.headers(token: "abc", url: "https://ductura.test/app/", hosts: nil).isEmpty)
    }
}
