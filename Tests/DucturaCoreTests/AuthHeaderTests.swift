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

    private let env = [AuthHeader.environmentKey: "abc"]

    func testTokenReadFromEnvironmentOnlyInSmokeWindowMode() {
        let test = LaunchOptions.parse(["--smoke-window", "/tmp/izmisljeni-izvjestaj"])
        XCTAssertEqual(AuthHeader.token(environment: env, options: test), "abc")
        XCTAssertNil(AuthHeader.token(environment: [:], options: test))
    }

    // A production launch (with or without a link, or with --smoke) never reads the environment token.
    func testProductionLaunchIgnoresEnvironmentToken() {
        let launches: [[String]] = [[], ["ductura://doc/izmisljeni-rad"], ["--smoke"], ["--smoke-out", "/tmp/x"],
                                    ["--smoke-window"], ["--smoke-window", "--smoke"]]
        for args in launches {
            XCTAssertNil(AuthHeader.token(environment: env, options: LaunchOptions.parse(args)), "\(args)")
        }
    }

    private let web = WebAddress.make(url: "https://ductura.test/app/", hosts: "ductura.test;drugi.test")

    func testHeaderOnlyForApiOnWebOrigin() {
        for url in ["https://ductura.test/api/v1/me", "https://ductura.test/api/v1/works/izmisljeni-rad?x=1#y",
                    "https://ductura.test/api/v1/"] {
            XCTAssertEqual(AuthHeader.headers(token: "abc", url: url, web: web), ["Authorization": "Bearer abc"], url)
        }
    }

    // HTML pages, other origins and paths that only look like the API get no token.
    func testNoHeaderForPagesOtherOriginsOrTrickPaths() {
        let refused = [
            "https://ductura.test/app/", "https://ductura.test/app/#/doc/izmisljeni-rad", "https://ductura.test/",
            "https://ductura.test/api/v1", "https://ductura.test/api/v10/me", "https://ductura.test/api/v2/me",
            "https://ductura.test/API/v1/me", "https://ductura.test/app/api/v1/me", "https://ductura.test?/api/v1/",
            "https://ductura.test/api/v1/../me", "https://ductura.test/api/v1/./me", "https://ductura.test/api/v1/..",
            "https://ductura.test/api/v1/%2e%2e/me", "https://ductura.test/api/v1/a%2Fb",
            "https://ductura.test/api/v1/a\\b", "https://ductura.test/api/v1/a b",
            "http://ductura.test/api/v1/me", "https://drugi.test/api/v1/me", "https://sub.ductura.test/api/v1/me",
            "https://ductura.test.zlo.test/api/v1/me", "https://ductura.test:444/api/v1/me",
            "https://ductura.test:443/api/v1/me", "https://demo@ductura.test/api/v1/me", "https://DUCTURA.test/api/v1/me",
            "//ductura.test/api/v1/me", "/api/v1/me", "",
        ]
        for url in refused {
            XCTAssertTrue(AuthHeader.headers(token: "abc", url: url, web: web).isEmpty, url)
        }
        XCTAssertTrue(AuthHeader.headers(token: "abc", url: nil, web: web).isEmpty)
    }

    func testNoHeaderWithoutTokenOrWebAddress() {
        let url = "https://ductura.test/api/v1/me"
        XCTAssertTrue(AuthHeader.headers(token: "a b", url: url, web: web).isEmpty)
        XCTAssertTrue(AuthHeader.headers(token: nil, url: url, web: web).isEmpty)
        XCTAssertTrue(AuthHeader.headers(token: "abc", url: url, web: nil).isEmpty)
    }

    // The window's first load is the web app page: even in test mode it carries no token.
    func testFirstWindowLoadCarriesNoToken() throws {
        let page = try XCTUnwrap(web?.url)
        let test = LaunchOptions.parse(["--smoke-window", "/tmp/izmisljeni-izvjestaj"])
        XCTAssertTrue(AuthHeader.headers(token: AuthHeader.token(environment: env, options: test),
                                         url: page, web: web).isEmpty)
    }
}
