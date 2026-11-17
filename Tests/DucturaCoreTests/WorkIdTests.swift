import CryptoKit
import Foundation
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

// Shared work-id vectors from the locked @ductura/contracts (DAN-1001): every vector goes through
// isValid or fromPathSegment. Without network the test fails on purpose; it never skips.
enum WorkIdVectors {
    struct Vector {
        let name: String
        let check: String
        let input: Any
        let accepted: Bool
        let id: String?
    }

    static let member = "package/vectors/work-id.json"
    static let format = "ductura-work-id-vectors-v1"
    /// Pinned by "check:accepted", so a vector that disappears or appears fails.
    static let counts = ["isWorkId:true": 11, "isWorkId:false": 23, "workIdFromPath:true": 5, "workIdFromPath:false": 9]
    /// sha256 of the sorted names joined by "\n", so a vector swapped for another of the same class fails too.
    static let names = "879ab64f7bfaf679886d6a2949a344270927477ddf39c1007ff58546b7c8c50b"

    static func namesHash(_ vectors: [Vector]) -> String {
        SHA256.hash(data: Data(vectors.map(\.name).sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func fail(_ text: String) -> VectorsError { VectorsError(description: text) }

    static func parseLock(_ data: Data) throws -> TestFakesLock {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(o.keys) == ["version", "url", "sha256", "operations"],
              let ops = o["operations"] as? [String], !ops.isEmpty, Set(ops).count == ops.count,
              let version = o["version"] as? String, ClientVersion.parse(version) != nil,
              let url = o["url"] as? String,
              url == "https://github.com/ductura/server/releases/download/contracts-v\(version)/ductura-contracts-\(version).tgz",
              let sha256 = o["sha256"] as? String, sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
        else { throw fail("contracts.lock.json nije ispravan: točno version (x.y.z), url izdanja te verzije, sha256 (64 mala heks znaka) i operations") }
        return TestFakesLock(version: version, url: url, sha256: sha256)
    }

    /// A real JSON bool; on Darwin `1 as? Bool` and `true as? Int` both succeed.
    static func bool(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    static func int(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return Int(exactly: n.doubleValue)
    }

    static func hasMarker(_ text: String) -> Bool { text.unicodeScalars.contains { $0.value >= 0x10_0000 } }

    /// A Swift String cannot hold a lone surrogate, so each lone `\uD800`-`\uDFFF` escape becomes the
    /// plane-16 marker U+100000 + offset. A file that already has a plane-16 character is refused, so a
    /// marker is never ambiguous.
    static func markLoneSurrogates(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.first == 0x7B, String(data: data, encoding: .utf8) != nil else { throw fail("work-id.json nije UTF-8 objekt bez BOM-a") }
        let plane16 = fail("work-id.json ima znak ravnine 16")
        if b.contains(0xF4) { throw plane16 }
        func unit(_ at: Int) -> UInt32? {
            guard at + 6 <= b.count, b[at] == 0x5C, b[at + 1] == 0x75,
                  b[(at + 2)..<(at + 6)].allSatisfy({ (0x30...0x39).contains($0) || (0x41...0x46).contains($0 & 0xDF) })
            else { return nil }
            return UInt32(String(decoding: b[(at + 2)..<(at + 6)], as: UTF8.self), radix: 16)
        }
        var out: [UInt8] = []
        var at = 0
        while at < b.count {
            guard b[at] == 0x5C, at + 1 < b.count else { out.append(b[at]); at += 1; continue }
            guard let u = unit(at) else { out += b[at...(at + 1)]; at += 2; continue }
            if (0xD800...0xDBFF).contains(u), let low = unit(at + 6), (0xDC00...0xDFFF).contains(low) {
                if u >= 0xDBC0 { throw plane16 }
                out += b[at..<(at + 12)]
                at += 12
                continue
            }
            if (0xD800...0xDFFF).contains(u) {
                let n = u - 0xD800
                out += Array(String(format: "\\u%04X\\u%04X", 0xDBC0 + (n >> 10), 0xDC00 + (n & 0x3FF)).utf8)
            } else {
                out += b[at..<(at + 6)]
            }
            at += 6
        }
        return Data(out)
    }

    static func parse(_ data: Data) throws -> [Vector] {
        let marked = try markLoneSurrogates(data)
        guard let top = try? JSONSerialization.jsonObject(with: marked) as? [String: Any],
              Set(top.keys) == ["format", "vectors"], top["format"] as? String == format,
              let list = top["vectors"] as? [[String: Any]], !list.isEmpty
        else { throw fail("work-id.json nije \(format) s nepraznim popisom vektora") }
        var names = Set<String>()
        return try list.map { (v: [String: Any]) throws -> Vector in
            let keys = Set(v.keys)
            let name = v["name"] as? String ?? ""
            guard keys.isSubset(of: ["name", "check", "input", "repeat", "accepted", "id"]),
                  !name.isEmpty, !hasMarker(name), names.insert(name).inserted,
                  let check = v["check"] as? String, check == "isWorkId" || check == "workIdFromPath",
                  let accepted = bool(v["accepted"]), keys.contains("input") != keys.contains("repeat"),
                  keys.contains("id") == (check == "workIdFromPath" && accepted)
            else { throw fail("vektor \(name): neispravna ili nedopuštena polja") }
            var input: Any = v["input"] ?? NSNull()
            if keys.contains("repeat") {
                guard let r = v["repeat"] as? [String: Any], Set(r.keys) == ["text", "count"],
                      let text = r["text"] as? String, !text.isEmpty, !hasMarker(text),
                      let count = int(r["count"]), (1...1024).contains(count)
                else { throw fail("vektor \(name): repeat mora biti text i count 1 do 1024") }
                input = String(repeating: text, count: count)
            }
            let id = v["id"] as? String
            guard keys.contains("id") == (id != nil), !hasMarker(id ?? ""),
                  check == "isWorkId" || (input as? String).map(hasMarker) == false
            else { throw fail("vektor \(name): id ili ulaz puta nije ispravan string") }
            return Vector(name: name, check: check, input: input, accepted: accepted, id: id)
        }
    }

    /// Throws on the first vector whose Swift outcome differs; returns how many ran, by "check:accepted".
    static func run(_ vectors: [Vector]) throws -> [String: Int] {
        var ran: [String: Int] = [:]
        for v in vectors {
            let same: Bool
            if let text = v.input as? String, !hasMarker(text) {
                same = v.check == "isWorkId"
                    ? WorkId.isValid(text) == v.accepted
                    : WorkId.fromPathSegment(text).map { Array($0.unicodeScalars) } == v.id.map { Array($0.unicodeScalars) }
            } else {
                same = !v.accepted // not a string, or a lone surrogate: no Swift String can carry it
            }
            guard same else { throw fail("vektor \(v.name): Swift se ne slaže s accepted \(v.accepted)") }
            ran["\(v.check):\(v.accepted)", default: 0] += 1
        }
        return ran
    }

    static func load() throws -> [Vector] {
        let lock = try parseLock(Data(contentsOf: TestFakesRelease.root.appendingPathComponent("contracts.lock.json")))
        let tarball = try TestFakesRelease.download(URL(string: lock.url)!)
        let actual = SHA256.hash(data: tarball).map { String(format: "%02x", $0) }.joined()
        guard actual == lock.sha256 else { throw fail("sha256 tarballa ne odgovara contracts.lock.json: dobiveno \(actual)") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ductura-contracts-\(UUID().uuidString).tgz")
        try tarball.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let pkg = try? JSONSerialization.jsonObject(with: TestFakesRelease.member("package/package.json", of: file)) as? [String: Any]
        guard pkg?["name"] as? String == "@ductura/contracts", pkg?["version"] as? String == lock.version else {
            throw fail("tarball nije @ductura/contracts \(lock.version)")
        }
        return try parse(TestFakesRelease.member(member, of: file))
    }

    static let release = Result { try load() }
}

extension WorkIdTests {
    func file(_ items: [String]) -> Data {
        Data(#"{"format":"ductura-work-id-vectors-v1","vectors":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    func runs(_ items: [String]) -> Bool { (try? WorkIdVectors.run(WorkIdVectors.parse(file(items)))) != nil }

    func testNeispravanContractsLockSeOdbija() throws {
        let url = "https://github.com/ductura/server/releases/download/contracts-v2.7.0/ductura-contracts-2.7.0.tgz"
        let sha = String(repeating: "a", count: 64)
        func json(_ v: String = "2.7.0", u: String = url, s: String = sha, ops: String = #"["platform.health.get"]"#, extra: String = "") -> String {
            #"{"version":"\#(v)","url":"\#(u)","sha256":"\#(s)","operations":\#(ops)\#(extra)}"#
        }
        XCTAssertEqual(try WorkIdVectors.parseLock(Data(json().utf8)), TestFakesLock(version: "2.7.0", url: url, sha256: sha))
        XCTAssertNoThrow(try WorkIdVectors.parseLock(Data(contentsOf: TestFakesRelease.root.appendingPathComponent("contracts.lock.json"))))
        let bad = [
            json("2.7"), json("2.7.1"), json(" 2.7.0"), json(u: url + "?x"), json(u: url.replacingOccurrences(of: "https", with: "http")),
            json(s: String(repeating: "A", count: 64)), json(s: String(sha.dropLast())), json(s: String(sha.dropLast()) + "\u{A0}"), json(s: String(sha.dropLast()) + "g"),
            json(s: String(sha.dropLast()) + "\u{7F}"), json(s: String(sha.dropLast()) + #"\t"#), json(ops: "[]"), json(ops: #"["a","a"]"#),
            json(ops: "[1]"), json(ops: "null"), json(extra: #","__proto__":{}"#), json(extra: #","toString":1"#),
            #"{"version":"2.7.0","url":"\#(url)","sha256":"\#(sha)"}"#, "[]", "",
        ]
        for text in bad { XCTAssertThrowsError(try WorkIdVectors.parseLock(Data(text.utf8)), text) }
    }

    func testNeispravnaDatotekaVektoraSeOdbija() {
        let ok = #"{"name":"a\r\n\tb","check":"isWorkId","input":"doc","accepted":true}"#
        XCTAssertTrue(runs([ok]))
        func v(_ fields: String) -> String { #"{"name":"x",\#(fields)}"# }
        let items = [
            [ok, ok], [], [v(#""check":"isWorkId","input":"doc","accepted":true,"__proto__":{}"#)],
            [v(#""check":"isWorkId","input":"doc","accepted":true,"toString":1"#)], [v(#""check":"toString","input":"doc","accepted":true"#)],
            [v(#""check":"isWorkId","input":"doc","repeat":{"text":"d","count":1},"accepted":true"#)], [v(#""check":"isWorkId","accepted":true"#)],
            [v(#""check":"isWorkId","repeat":{"text":"d","count":0},"accepted":true"#)], [v(#""check":"isWorkId","repeat":{"text":"d","count":1025},"accepted":false"#)],
            [v(#""check":"isWorkId","repeat":{"text":"d","count":1.5},"accepted":true"#)], [v(#""check":"isWorkId","repeat":{"text":"d","count":true},"accepted":true"#)],
            [v(#""check":"isWorkId","repeat":{"text":"d","count":"1"},"accepted":true"#)], [v(#""check":"isWorkId","repeat":{"text":"","count":1},"accepted":false"#)],
            [v(#""check":"isWorkId","repeat":{"text":"d","count":1,"x":1},"accepted":true"#)], [v(#""check":"isWorkId","input":"doc","accepted":1"#)],
            [v(#""check":"isWorkId","input":"doc","accepted":"true""#)], [v(#""check":"isWorkId","input":"doc""#)],
            [v(#""check":"isWorkId","input":"doc","accepted":true,"id":"doc""#)], [v(#""check":"workIdFromPath","input":"%00","accepted":false,"id":"x""#)],
            [v(#""check":"workIdFromPath","input":"doc","accepted":true"#)], [v(#""check":"workIdFromPath","input":7,"accepted":false"#)],
            [v(#""check":"workIdFromPath","input":"doc","accepted":true,"id":7"#)], [#"{"check":"isWorkId","input":"doc","accepted":true}"#],
            [#"{"name":"","check":"isWorkId","input":"doc","accepted":true}"#], [v(#""check":"isWorkId","input":"doc"# + "\u{100000}" + #"","accepted":true"#)],
            [v(#""check":"isWorkId","input":"doc\udbc0\udc00","accepted":true"#)], [v(#""check":"isWorkId","input":"doc\uDBFF\uDFFF","accepted":true"#)],
        ]
        for list in items { XCTAssertThrowsError(try WorkIdVectors.parse(file(list)), list.joined()) }
        let other = [#"{"vectors":[\#(ok)]}"#, #"{"format":"x","vectors":[\#(ok)]}"#, #"{"format":"ductura-work-id-vectors-v1","vectors":[\#(ok)],"x":1}"#, "[]", ""]
        for text in other + ["\u{FEFF}" + String(decoding: file([ok]), as: UTF8.self), " " + String(decoding: file([ok]), as: UTF8.self)] {
            XCTAssertThrowsError(try WorkIdVectors.parse(Data(text.utf8)), text)
        }
        XCTAssertThrowsError(try WorkIdVectors.parse(Data([0x7B, 0xFF, 0x7D])))
    }

    func testNeparniSurogat() throws {
        func vector(_ input: String, _ accepted: Bool, check: String = "isWorkId") -> String {
            #"{"name":"s","check":"\#(check)","input":"\#(input)","accepted":\#(accepted)}"#
        }
        for input in [#"doc\ud800"#, #"\udc00doc"#, #"\ud800\ud800"#, #"\uDBFFx"#, #"\\\ud800"#] {
            XCTAssertTrue(runs([vector(input, false)]), input)
            XCTAssertFalse(runs([vector(input, true)]), input)
            XCTAssertThrowsError(try WorkIdVectors.parse(file([vector(input, false, check: "workIdFromPath")])), input)
        }
        XCTAssertTrue(runs([vector(#"\\ud800"#, true)])) // escaped backslash: six characters of text
        let pair = try WorkIdVectors.parse(file([vector(#"\ud83d\ude00"#, true)]))
        XCTAssertEqual(pair.first?.input as? String, "\u{1F600}")
        XCTAssertThrowsError(try WorkIdVectors.parse(file([#"{"name":"r","check":"isWorkId","repeat":{"text":"\ud800","count":1},"accepted":false}"#])))
        // A marker in the id would equal a decoded U+100000 from the path; in a name it hides a lone surrogate.
        XCTAssertThrowsError(try WorkIdVectors.parse(file([#"{"name":"i","check":"workIdFromPath","input":"%F4%80%80%80","accepted":true,"id":"\ud800"}"#])))
        XCTAssertThrowsError(try WorkIdVectors.parse(file([#"{"name":"n\ud800","check":"isWorkId","input":"doc","accepted":true}"#])))
    }

    func testPromijenjenVektorRusiProvjeru() throws {
        let base = [
            #"{"name":"a","check":"isWorkId","input":"doc'1","accepted":true}"#,
            #"{"name":"b","check":"workIdFromPath","input":"rad-%C4%8D","accepted":true,"id":"rad-\u010d"}"#,
            #"{"name":"c","check":"isWorkId","repeat":{"text":"d","count":256},"accepted":true}"#,
            #"{"name":"d","check":"isWorkId","input":null,"accepted":false}"#,
        ]
        XCTAssertEqual(try WorkIdVectors.run(WorkIdVectors.parse(file(base))), ["isWorkId:true": 2, "workIdFromPath:true": 1, "isWorkId:false": 1])
        let changes = [(0, "doc'1", #"doc\t1"#), (0, "true", "false"), (1, #"rad-\u010d""#, #"rad-c\u030c""#),
                       (1, #""workIdFromPath""#, #""isWorkId""#), (2, "256", "257"), (3, "false", "true")]
        for (index, from, to) in changes {
            var list = base
            list[index] = list[index].replacingOccurrences(of: from, with: to)
            XCTAssertNotEqual(Array(list[index].utf8), Array(base[index].utf8))
            XCTAssertFalse(runs(list), list[index])
        }
    }

    func testSvakiVektorIdaRadaIzZakljucanogUgovora() throws {
        let vectors = try WorkIdVectors.release.get()
        XCTAssertEqual(try WorkIdVectors.run(vectors), WorkIdVectors.counts)
        XCTAssertEqual(WorkIdVectors.namesHash(vectors), WorkIdVectors.names)
    }
}
