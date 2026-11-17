import CryptoKit
import Foundation
import XCTest
@testable import DucturaCore

// Health vectors from the locked @ductura/test-fakes release (DAN-999): every `platform.health.get`
// vector goes through the generated decoder and ClientVersion.decide. The bridge from an HTTP answer
// to HealthReading is local to the test (the real server call is DAN-945-2). Without network the
// test fails on purpose; it never skips.
struct VectorsError: Error, CustomStringConvertible {
    let description: String
}

struct TestFakesLock: Equatable {
    let version: String
    let url: String
    let sha256: String
}

struct HealthVector {
    let name: String
    let status: Int
    let body: Data
}

enum TestFakesRelease {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let packageMember = "package/package.json"
    static let vectorsMember = "package/server/contracts/generated/fake-server/vectors.json"
    static let clients = ["1.0.0", "0.9.9"]
    /// Outcome for each client in `clients`, by vector name.
    static let expected: [String: [ClientVersionDecision]] = [
        "alive": [.open, .open],
        "alive-with-version": [.open, .open],
        "alive-current": [.open, .updateRequired(minimum: "1.0.0")],
        "degraded": [.open, .updateRequired(minimum: "1.0.0")],
        "internal": [.serverUnavailable, .serverUnavailable],
        "too-many-requests": [.serverUnavailable, .serverUnavailable],
    ]
    /// Everything `decide` reads, by vector name (DAN-1001): a change that matters only for a
    /// client version outside `clients` (e.g. `alive` with minClientVersion 0.9.9) still fails.
    static let readings: [String: HealthReading] = [
        "alive": .answered(status: "ok", minClientVersion: nil),
        "alive-with-version": .answered(status: "ok", minClientVersion: nil),
        "alive-current": .answered(status: "ok", minClientVersion: "1.0.0"),
        "degraded": .answered(status: "ok", minClientVersion: "1.0.0"),
        "internal": .unavailable,
        "too-many-requests": .unavailable,
    ]

    static func parseLock(_ data: Data) throws -> TestFakesLock {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["version", "url", "sha256"],
              let version = object["version"] as? String, ClientVersion.parse(version) != nil,
              let url = object["url"] as? String,
              url == "https://github.com/ductura/server/releases/download/test-fakes-v\(version)/ductura-test-fakes-\(version).tgz",
              let sha256 = object["sha256"] as? String, sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
        else { throw VectorsError(description: "test-fakes.lock.json nije ispravan: točno version (x.y.z), url izdanja te verzije i sha256 (64 mala heks znaka)") }
        return TestFakesLock(version: version, url: url, sha256: sha256)
    }

    static func checkSha256(_ tarball: Data, _ lock: TestFakesLock) throws {
        let actual = SHA256.hash(data: tarball).map { String(format: "%02x", $0) }.joined()
        guard actual == lock.sha256 else {
            throw VectorsError(description: "sha256 tarballa ne odgovara test-fakes.lock.json: očekivano \(lock.sha256), dobiveno \(actual)")
        }
    }

    static func checkPackage(_ json: Data, _ lock: TestFakesLock) throws {
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        guard object?["name"] as? String == "@ductura/test-fakes", object?["version"] as? String == lock.version else {
            throw VectorsError(description: "tarball nije @ductura/test-fakes \(lock.version)")
        }
    }

    static func download(_ url: URL) throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 60
        var result: Result<Data, Error> = .failure(VectorsError(description: "preuzimanje \(url) nije završilo"))
        let done = DispatchSemaphore(value: 0)
        URLSession(configuration: config).dataTask(with: url) { data, response, error in
            defer { done.signal() }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error { result = .failure(error) }
            else if status == 200, let data { result = .success(data) }
            else { result = .failure(VectorsError(description: "preuzimanje \(url) vratilo je HTTP \(status)")) }
        }.resume()
        done.wait()
        return try result.get()
    }

    /// One member to stdout only: nothing from the tarball is written to disk.
    static func member(_ name: String, of tarball: URL) throws -> Data {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xOzf", tarball.path, name]
        let out = Pipe()
        tar.standardOutput = out
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0, !data.isEmpty else { throw VectorsError(description: "u tarballu nema \(name)") }
        return data
    }

    static func healthVectors(_ json: Data) throws -> [HealthVector] {
        guard let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
            throw VectorsError(description: "vectors.json nije popis objekata")
        }
        return try list.filter { $0["route"] as? String == "platform.health.get" }.map { vector in
            let response = vector["response"] as? [String: Any]
            guard let name = vector["name"] as? String, let status = response?["status"] as? Int, let body = response?["body"] else {
                throw VectorsError(description: "health vektor bez imena, statusa ili tijela")
            }
            return HealthVector(name: name, status: status, body: try JSONSerialization.data(withJSONObject: body, options: .fragmentsAllowed))
        }
    }

    static func load() throws -> [HealthVector] {
        let lock = try parseLock(Data(contentsOf: root.appendingPathComponent("test-fakes.lock.json")))
        let tarball = try download(URL(string: lock.url)!)
        try checkSha256(tarball, lock)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ductura-test-fakes-\(UUID().uuidString).tgz")
        try tarball.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try checkPackage(member(packageMember, of: file), lock)
        return try healthVectors(member(vectorsMember, of: file))
    }

    static let release = Result { try load() }

    /// Test-only bridge, as documented on HealthReading: 200 with a decodable body is an answer.
    static func reading(_ vector: HealthVector) -> HealthReading {
        guard vector.status == 200, let r = try? JSONDecoder().decode(PlatformHealthGetResponse.self, from: vector.body) else {
            return .unavailable
        }
        return .answered(status: r.status, minClientVersion: r.minClientVersion)
    }

    static func check(_ vectors: [HealthVector]) throws {
        let names = vectors.map(\.name)
        guard names.count == Set(names).count, Set(names) == Set(expected.keys) else {
            throw VectorsError(description: "health vektori \(names.sorted()) nisu točno tablica \(expected.keys.sorted())")
        }
        for vector in vectors {
            guard reading(vector) == readings[vector.name] else {
                throw VectorsError(description: "vektor \(vector.name): \(reading(vector)), očekivano \(readings[vector.name].map { "\($0)" } ?? "nil")")
            }
            let outcomes = clients.map { ClientVersion.decide(reading(vector), clientVersion: $0) }
            guard outcomes == expected[vector.name] else {
                throw VectorsError(description: "vektor \(vector.name): \(outcomes), očekivano \(expected[vector.name]!)")
            }
        }
    }
}

final class ContractVectorsTests: XCTestCase {
    let lock = TestFakesLock(version: "3.0.1", url: "", sha256: String(repeating: "0", count: 64))

    func vector(_ name: String, _ status: Int = 200, _ body: String = #"{"status":"ok"}"#) -> HealthVector {
        HealthVector(name: name, status: status, body: Data(body.utf8))
    }

    var valid: [HealthVector] {
        let current = #"{"status":"ok","state":"ok","minClientVersion":"1.0.0"}"#
        return [vector("alive"), vector("alive-with-version", 200, #"{"status":"ok","version":"1.2.0"}"#),
                vector("alive-current", 200, current), vector("degraded", 200, current.replacingOccurrences(of: #""ok","m"#, with: #""degraded","m"#)),
                vector("internal", 500, #"{"status":500}"#), vector("too-many-requests", 429, #"{"status":429}"#)]
    }

    func message(_ body: () throws -> Void) -> String {
        do { try body(); return "" } catch { return "\(error)" }
    }

    func testKriviSha256ULockuPadaSJasnomPorukom() {
        let text = message { try TestFakesRelease.checkSha256(Data("tarball".utf8), lock) }
        XCTAssertTrue(text.hasPrefix("sha256 tarballa ne odgovara test-fakes.lock.json: očekivano \(lock.sha256), dobiveno "), text)
    }

    func testNeispravanLockSeOdbija() throws {
        let url = "https://github.com/ductura/server/releases/download/test-fakes-v3.0.1/ductura-test-fakes-3.0.1.tgz"
        let sha = String(repeating: "a", count: 64)
        func json(_ version: String = "3.0.1", u: String = url, s: String = sha, extra: String = "") -> String {
            #"{"version":"\#(version)","url":"\#(u)","sha256":"\#(s)"\#(extra)}"#
        }
        XCTAssertEqual(try TestFakesRelease.parseLock(Data(json().utf8)), TestFakesLock(version: "3.0.1", url: url, sha256: sha))
        let bad = [
            json("3.0", u: url.replacingOccurrences(of: "3.0.1", with: "3.0")),
            json("3.0.2"), json("03.0.1"), json(" 3.0.1"), json(u: url + "?x"), json(u: url.replacingOccurrences(of: "https", with: "http")),
            json(s: String(repeating: "A", count: 64)), json(s: String(sha.dropLast())), json(s: sha + "a"), json(s: String(sha.dropLast()) + "\u{A0}"),
            json(s: String(sha.dropLast()) + "\u{7F}"), json(s: String(sha.dropLast()) + "\t"), json(extra: #","operations":[]"#),
            json(extra: #","__proto__":{}"#), #"{"version":"3.0.1","url":"\#(url)"}"#, #"{"version":3,"url":"\#(url)","sha256":"\#(sha)"}"#, "[]", "",
        ]
        for text in bad {
            XCTAssertThrowsError(try TestFakesRelease.parseLock(Data(text.utf8)), text)
        }
    }

    func testPaketDrugogImenaIliVerzijeSeOdbija() throws {
        XCTAssertNoThrow(try TestFakesRelease.checkPackage(Data(#"{"name":"@ductura/test-fakes","version":"3.0.1"}"#.utf8), lock))
        for json in [#"{"name":"@ductura/test-fakes","version":"3.0.0"}"#, #"{"name":"@ductura/contracts","version":"3.0.1"}"#, #"{"name":"@ductura/test-fakes"}"#, "[]"] {
            XCTAssertThrowsError(try TestFakesRelease.checkPackage(Data(json.utf8), lock), json)
        }
    }

    func testTarballBezClanaDajeJasnuGresku() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("ductura-nema-\(UUID().uuidString).tgz")
        XCTAssertEqual(message { _ = try TestFakesRelease.member("package/package.json", of: missing) }, "u tarballu nema package/package.json")
    }

    func testSkupVektoraMoraBitiTocnoTablica() throws {
        XCTAssertNoThrow(try TestFakesRelease.check(valid))
        for vectors in [Array(valid.dropLast()), valid + [vector("unknown")], valid + [vector("alive")]] {
            XCTAssertThrowsError(try TestFakesRelease.check(vectors))
        }
    }

    func testPromijenjenVektorDajeDrugiIshod() {
        let changed = [vector("alive", 200, #"{"status":"ok","minClientVersion":"9.0.0"}"#), vector("alive", 503), vector("alive", 200, #"{"status":"down"}"#)]
        for vector in changed {
            XCTAssertThrowsError(try TestFakesRelease.check(valid.filter { $0.name != "alive" } + [vector]))
        }
    }

    func testSvakiHealthVektorDajeOcekivaniIshod() throws {
        let vectors = try TestFakesRelease.release.get()
        try TestFakesRelease.check(vectors)
        XCTAssertEqual(Set(vectors.map(\.name)), Set(TestFakesRelease.expected.keys))
    }
}
