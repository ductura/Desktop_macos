import XCTest
@testable import DucturaCore

// Cases copied from ductura/server contracts/work-id.test.ts at
// 7b78d9b071dc2cb54392840bcdf353e68be865e3 (S-1H.1-c), plus the input classes
// of the DAN-882 contract. Invented ids only. The server's "not a string"
// cases (undefined, 7, {}, ...) cannot be expressed: the Swift type is String.
final class WorkIdTests: XCTestCase {
    static let max = WorkId.maxLength
    static let web = WebAddress.make(url: "https://ductura.test/app/", hosts: "ductura.test")!

    /// Refused by isValid, so by the link and the URL too. Negative cases first.
    static let invalid: [String] = [
        "", " ",
        "d" + String(repeating: "d", count: max), String(repeating: "😀", count: max + 1),
        "doc\u{0}", "a\tb", "a\nb", "a\r\nb", "a\u{7F}b", "a\u{5}b", "a\u{1F}b", "a\u{85}b", "a\u{9F}b",
        " doc", "doc ", "\u{A0}doc", "doc\u{2028}", "\u{3000}doc", "\u{FEFF}doc", "doc\u{FEFF}",
        "\u{1680}doc", "doc\u{2029}", "\u{202F}doc", "\tdoc", "doc\r",
        String(repeating: "🇭🇷", count: max / 2 + 1),
    ]

    /// Accepted as opaque data, as the database CHECK does.
    static let valid: [String] = [
        "doc-izmisljeni-1", "6f1c2a9e-0b7d-4c1e-9a55-3d2e8f0b1a77",
        String(repeating: "d", count: max), String(repeating: "😀", count: max),
        "doc'1", "doc';DROP TABLE x;--", "%00", "../doc", "../../etc", "..\\doc", "C:\\x",
        "rad-čćžšđ-ŽĆ", "문서-1", "doc\u{FFFD}", "a\u{200B}b", "a b",
        "\u{200B}doc", "doc\u{180E}", "a\u{FEFF}b", "a+b", "/", String(repeating: "🇭🇷", count: max / 2),
    ]

    func testRefusesEveryInvalidId() {
        for id in Self.invalid { XCTAssertFalse(WorkId.isValid(id), "\(id.unicodeScalars.map { $0.value })") }
    }

    func testAcceptsEveryValidId() {
        for id in Self.valid { XCTAssertTrue(WorkId.isValid(id), id) }
    }

    /// Scalars, not `==`: String equality is canonical (`c\u{30C}` == `č`).
    func same(_ a: String?, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map { Array($0.unicodeScalars) }, Array(b.unicodeScalars), b, file: file, line: line)
    }

    func testCountsScalarsNotUTF16Units() {
        XCTAssertEqual(String(repeating: "😀", count: Self.max).utf16.count, 2 * Self.max)
        XCTAssertTrue(WorkId.isValid(String(repeating: "😀", count: Self.max)))
    }

    func testPathSegmentRefusesBrokenOrBadEncoding() {
        let bad = ["%00", "doc%00", "", "%", "%zz", "%C4", "%ED%A0%80", "%ED%B0%80doc",
                   "%20doc", "%C2%A0doc", "doc%0D%0A", "%EF%BB%BFdoc", "doc%EF%BB%BF", "\u{FEFF}doc", "doc%ED%A0%80",
                   "a%C2%85b", "%C0%80", "%E0%80%80", "%F4%90%80%80", "%FF", "a%2", "%%",
                   String(repeating: "d", count: Self.max + 1)]
        for segment in bad { XCTAssertNil(WorkId.fromPathSegment(segment), segment) }
    }

    func testPathSegmentDecodesExactlyOnce() {
        same(WorkId.fromPathSegment("doc-izmisljeni-1"), "doc-izmisljeni-1")
        same(WorkId.fromPathSegment("rad-%C4%8D"), "rad-\u{10D}")
        same(WorkId.fromPathSegment("rad-%c4%8d"), "rad-\u{10D}")
        same(WorkId.fromPathSegment("rad-c%CC%8C"), "rad-c\u{30C}")
        same(WorkId.fromPathSegment("%2500"), "%00")
        same(WorkId.fromPathSegment("doc%27%3B"), "doc';")
        same(WorkId.fromPathSegment("..%2Fdoc"), "../doc")
        same(WorkId.fromPathSegment("%2F"), "/") // a valid id under the rule: opaque data
        same(WorkId.fromPathSegment("a+b"), "a+b") // no form decoding
        same(WorkId.fromPathSegment("a%EF%BB%BFb"), "a\u{FEFF}b")
    }

    func testLinkGivesNoIdForAnyInvalidId() {
        for id in Self.invalid {
            XCTAssertNil(LaunchOptions.parse(["ductura://doc/" + WorkId.encode(id)]).openDocumentId)
        }
        for link in ["ductura://doc/a/b", "ductura://doc/a?b", "ductura://doc/a#b", "ductura://doc/a//",
                     "ductura://doc/", "ductura://doc//", "ductura://doc/%", "ductura://doc//x",
                     "ductura://doc/../doc", "ductura://doc/demo-1//"] {
            XCTAssertNil(LaunchOptions.parse([link]).openDocumentId, link)
        }
    }

    func testLinkGivesTheDecodedValidId() {
        for id in Self.valid {
            same(LaunchOptions.parse(["ductura://doc/" + WorkId.encode(id)]).openDocumentId, id)
        }
        same(LaunchOptions.parse(["DUCTURA://DOC/demo-1/"]).openDocumentId, "demo-1")
        same(LaunchOptions.parse(["ductura://doc/..%2Fdoc"]).openDocumentId, "../doc")
        // The last link decides, as before; an invalid last one leaves no id.
        same(LaunchOptions.parse(["ductura://doc/a", "ductura://doc/b"]).openDocumentId, "b")
        XCTAssertNil(LaunchOptions.parse(["ductura://doc/a", "ductura://doc/%00"]).openDocumentId)
    }

    func testInvalidIdNeverReachesTheURL() {
        for id in Self.invalid {
            XCTAssertNil(WorkId.documentURL(web: Self.web, id: id))
            XCTAssertNil(WorkId.documentURL(web: Self.web, id: LaunchOptions(openDocumentId: id).openDocumentId))
        }
        XCTAssertNil(WorkId.documentURL(web: Self.web, id: nil))
    }

    func testURLEscapesEveryIdAndRoundTrips() {
        let prefix = "https://ductura.test/app/#/doc/"
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%")
        for id in Self.valid {
            let url = WorkId.documentURL(web: Self.web, id: id)?.absoluteString ?? ""
            XCTAssertTrue(url.hasPrefix(prefix), id)
            let tail = String(url.dropFirst(prefix.count))
            XCTAssertTrue(tail.unicodeScalars.allSatisfy(unreserved.contains), tail)
            same(WorkId.fromPathSegment(tail), id)
        }
        XCTAssertEqual(WorkId.documentURL(web: Self.web, id: "../x")?.absoluteString, prefix + "..%2Fx")
        XCTAssertEqual(WorkId.documentURL(web: Self.web, id: "\u{10D}")?.absoluteString, prefix + "%C4%8D")
    }
}
