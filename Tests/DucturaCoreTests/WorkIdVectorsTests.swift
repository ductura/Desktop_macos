import CryptoKit
import Foundation
import XCTest
@testable import DucturaCore

private enum WorkIdRelease {
    static let lockFile = "contracts.lock.json"
    static let vectorsMember = "package/vectors/work-id.json"

    struct Vector {
        enum Check: String {
            case isWorkId, workIdFromPath
        }

        enum Input {
            case string(String)
            case loneSurrogate(segment: String)
            case nonString
        }

        var name: String
        let check: Check
        let input: Input
        var accepted: Bool
        var id: String?
    }

    static func load() throws -> [Vector] {
        let lock = try Data(contentsOf: TestFakesRelease.root.appendingPathComponent(lockFile))
        let (url, sha256) = try parseLock(lock)
        let tarball = try TestFakesRelease.download(url)
        try verify(tarball, sha256: sha256)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ductura-contracts-\(UUID().uuidString).tgz")
        defer { try? FileManager.default.removeItem(at: file) }
        try tarball.write(to: file)
        return try parseVectors(TestFakesRelease.member(vectorsMember, of: file))
    }

    static func parseLock(_ data: Data) throws -> (URL, String) {
        guard case let .object(fields)? = StrictJSON.parse(data),
              Set(fields.keys) == ["version", "url", "sha256", "operations"],
              case let .string(version)? = fields["version"], ClientVersion.parse(version) != nil,
              case let .string(address)? = fields["url"],
              address == "https://github.com/ductura/Institution_server/releases/download/contracts-v\(version)/ductura-contracts-\(version).tgz",
              let url = URL(string: address),
              case let .string(sha256)? = fields["sha256"], sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }),
              case let .array(operations)? = fields["operations"], !operations.isEmpty,
              Set(operations.compactMap({ value -> String? in
                  if case let .string(operation) = value, !operation.isEmpty { return operation }
                  return nil
              })).count == operations.count
        else { throw failure("neispravan \(lockFile)") }
        return (url, sha256)
    }

    static func verify(_ tarball: Data, sha256: String) throws {
        let actual = digest(tarball)
        guard actual == sha256 else {
            throw failure("sha256 tarballa ne odgovara \(lockFile): očekivano \(sha256), dobiveno \(actual)")
        }
    }

    static func parseVectors(_ data: Data) throws -> [Vector] {
        let (json, surrogates) = try projectLoneSurrogates(data)
        guard case let .object(root)? = StrictJSON.parse(json),
              Set(root.keys) == ["format", "vectors"],
              root["format"] == .string("ductura-work-id-vectors-v1"),
              case let .array(entries)? = root["vectors"], !entries.isEmpty
        else { throw failure("neispravan format datoteke \(vectorsMember)") }

        var names = Set<String>()
        return try entries.map { entry in
            guard case let .object(fields) = entry,
                  case let .string(name)? = fields["name"], !name.isEmpty,
                  surrogates[name] == nil, names.insert(name).inserted,
                  case let .string(checkName)? = fields["check"], let check = Vector.Check(rawValue: checkName),
                  case let .bool(accepted)? = fields["accepted"]
            else { throw failure("neispravan vektor ili dvostruko ime") }

            let inputKey = fields["input"] != nil ? "input" : "repeat"
            let needsID = accepted && check == .workIdFromPath
            var keys: Set<String> = ["name", "check", "accepted", inputKey]
            if needsID { keys.insert("id") }
            guard Set(fields.keys) == keys else { throw failure("\(name): neispravni ključevi") }

            var id: String?
            if needsID {
                guard case let .string(value)? = fields["id"], surrogates[value] == nil else {
                    throw failure("\(name): id mora biti string")
                }
                id = value
            }

            let input: Vector.Input
            if let value = fields["input"] {
                if case let .string(text) = value {
                    input = surrogates[text].map { .loneSurrogate(segment: $0) } ?? .string(text)
                } else {
                    input = .nonString
                }
            } else {
                guard case let .object(repetition)? = fields["repeat"],
                      Set(repetition.keys) == ["text", "count"],
                      case let .string(text)? = repetition["text"],
                      case let .number(rawCount)? = repetition["count"],
                      let count = Int(rawCount), (1...1024).contains(count)
                else { throw failure("\(name): neispravan repeat") }
                input = surrogates[text].map { .loneSurrogate(segment: $0) }
                    ?? .string(String(repeating: text, count: count))
            }
            return Vector(name: name, check: check, input: input, accepted: accepted, id: id)
        }
    }

    // StrictJSON rejects unpaired UTF-16 surrogates. Give only those string tokens temporary
    // names, keeping valid escapes and duplicate-key checks in StrictJSON. Use an invalid
    // UTF-8 segment for the surrogate when passing it to LaunchOptions (Swift has no such scalar).
    private static func projectLoneSurrogates(_ data: Data) throws -> (Data, [String: String]) {
        guard let source = String(data: data, encoding: .utf8) else { throw failure("neispravan UTF-8") }
        let strings = try NSRegularExpression(pattern: #""(?:[^"\\]|\\[\s\S])*""#)
        let escapes = try NSRegularExpression(
            pattern: #"\\\\|\\u[dD][89a-bA-B][0-9a-fA-F]{2}\\u[dD][c-fC-F][0-9a-fA-F]{2}|\\u([dD][89a-fA-F][0-9a-fA-F]{2})"#
        )
        let raw = source as NSString
        var usedNames = Set<String>()
        var edits: [(range: NSRange, token: String, codeUnit: UInt16)] = []
        for match in strings.matches(in: source, range: NSRange(location: 0, length: raw.length)) {
            let token = raw.substring(with: match.range)
            if case let .string(text)? = StrictJSON.parse(Data(token.utf8)) {
                usedNames.insert(text)
                continue
            }
            let tokenRange = NSRange(token.startIndex..., in: token)
            let lone = escapes.matches(in: token, range: tokenRange).filter { $0.range(at: 1).location != NSNotFound }
            guard let first = lone.first,
                  let codeUnit = UInt16((token as NSString).substring(with: first.range(at: 1)), radix: 16)
            else { throw failure("neispravan JSON string") }

            let repaired = NSMutableString(string: token)
            for escape in lone.reversed() { repaired.replaceCharacters(in: escape.range, with: #"\u0000"#) }
            guard case .string? = StrictJSON.parse(Data((repaired as String).utf8)) else {
                throw failure("neispravan JSON string uz surogat")
            }
            edits.append((match.range, token, codeUnit))
        }

        let projected = NSMutableString(string: source)
        var surrogates: [String: String] = [:]
        var namesByToken: [String: String] = [:]
        for edit in edits.reversed() {
            var name = namesByToken[edit.token] ?? "work-id:surrogate:\(edit.range.location)"
            if namesByToken[edit.token] == nil {
                while !usedNames.insert(name).inserted { name += "_" }
                namesByToken[edit.token] = name
                let code = edit.codeUnit
                surrogates[name] = String(format: "%%ED%%%02X%%%02X", 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
            }
            projected.replaceCharacters(in: edit.range, with: "\"\(name)\"")
        }
        return (Data((projected as String).utf8), surrogates)
    }

    static func checkInventory(_ vectors: [Vector]) throws {
        let names = vectors.map(\.name).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        guard names.count == 48,
              digest(Data(names.joined(separator: "\n").utf8)) == "879ab64f7bfaf679886d6a2949a344270927477ddf39c1007ff58546b7c8c50b"
        else { throw failure("promijenjen skup zaključanih vektora (\(names.count)): \(names)") }
    }

    static func checkOutcome(_ vector: Vector) throws {
        let arguments: [String]
        let expected: String?
        switch vector.input {
        case let .string(input):
            // Raw IDs must survive the link syntax. Path vectors already contain a wire segment.
            let segment = vector.check == .isWorkId ? input
                .replacingOccurrences(of: "%", with: "%25", options: .literal)
                .replacingOccurrences(of: "/", with: "%2F", options: .literal)
                .replacingOccurrences(of: "?", with: "%3F", options: .literal)
                .replacingOccurrences(of: "#", with: "%23", options: .literal) : input
            arguments = ["ductura://doc/\(segment)"]
            expected = vector.accepted ? (vector.check == .isWorkId ? input : vector.id) : nil
        case let .loneSurrogate(segment):
            guard !vector.accepted else { throw failure("\(vector.name): prihvaćen usamljeni surogat") }
            arguments = ["ductura://doc/\(segment)"]
            expected = nil
        case .nonString:
            guard !vector.accepted else { throw failure("\(vector.name): prihvaćen ulaz koji nije string") }
            arguments = []
            expected = nil
        }
        let actual = LaunchOptions.parse(arguments).openDocumentId
        guard actual.map({ Array($0.utf8) }) == expected.map({ Array($0.utf8) }) else {
            throw failure("\(vector.name): očekivano \(String(reflecting: expected)), dobiveno \(String(reflecting: actual))")
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func failure(_ reason: String) -> VectorsError {
        VectorsError(description: "work-id vektori: \(reason)")
    }
}

final class WorkIdVectorsTests: XCTestCase {
    func testLockedWorkIdVectorsThroughLaunchOptions() throws {
        let vectors = try WorkIdRelease.load()
        try WorkIdRelease.checkInventory(vectors)
        for vector in vectors {
            try WorkIdRelease.checkOutcome(vector)
        }

        var renamed = vectors
        renamed[0].name += " (izmijenjeno)"
        XCTAssertThrowsError(try WorkIdRelease.checkInventory(renamed))
        XCTAssertThrowsError(try WorkIdRelease.checkInventory(Array(vectors.dropLast())))
        XCTAssertThrowsError(try WorkIdRelease.checkInventory(vectors + [vectors[0]]))
        for vector in vectors {
            var changed = vector
            changed.accepted.toggle()
            changed.id = changed.accepted ? "izmijenjeni-id" : nil
            XCTAssertThrowsError(try WorkIdRelease.checkOutcome(changed), vector.name)
            if vector.id != nil {
                changed = vector
                changed.id = "izmijenjeni-id"
                XCTAssertThrowsError(try WorkIdRelease.checkOutcome(changed), vector.name)
            }
        }
    }

    func testWrongTarballSHAIsAnError() {
        let wrong = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try WorkIdRelease.verify(Data("tarball".utf8), sha256: wrong)) { error in
            XCTAssertTrue(String(describing: error).contains("sha256 tarballa ne odgovara contracts.lock.json"))
        }
    }

    func testLockRequiresExactKeysAndTypes() throws {
        let sha = String(repeating: "a", count: 64)
        let url = "https://github.com/ductura/Institution_server/releases/download/contracts-v2.7.0/ductura-contracts-2.7.0.tgz"
        let lock = #"{"version":"2.7.0","url":"\#(url)","sha256":"\#(sha)","operations":["platform.health.get"]}"#
        let (parsedURL, parsedSHA) = try WorkIdRelease.parseLock(Data(lock.utf8))
        XCTAssertEqual(parsedURL.absoluteString, url)
        XCTAssertEqual(parsedSHA, sha)
        for invalid in [
            lock.replacingOccurrences(of: #""version":"2.7.0""#, with: #""version":270"#),
            lock.replacingOccurrences(of: #","operations":["platform.health.get"]"#, with: ""),
            lock.replacingOccurrences(of: #""operations":["platform.health.get"]"#, with: #""operations":[true]"#),
            lock.replacingOccurrences(of: #""version":"2.7.0""#, with: #""extra":0,"version":"2.7.0""#),
            lock.replacingOccurrences(of: #""version":"2.7.0""#, with: #""version":"2.7.0","version":"2.7.0""#),
        ] {
            XCTAssertThrowsError(try WorkIdRelease.parseLock(Data(invalid.utf8)), invalid)
        }
    }

    func testVectorSchemaAndNonStringInput() throws {
        func parse(_ vector: String) throws -> [WorkIdRelease.Vector] {
            let json = #"{"format":"ductura-work-id-vectors-v1","vectors":[\#(vector)]}"#
            return try WorkIdRelease.parseVectors(Data(json.utf8))
        }

        for vector in [
            #"{"name":"n","check":"isWorkId","input":"doc","accepted":true,"extra":0}"#,
            #"{"name":"n","check":"isWorkId","input":"doc"}"#,
            #"{"name":"n","check":"isWorkId","input":"doc","accepted":"true"}"#,
            #"{"name":"n","name":"n","check":"isWorkId","input":"doc","accepted":true}"#,
            #"{"name":"n","check":"isWorkId","input":"doc","repeat":{"text":"d","count":1},"accepted":true}"#,
            #"{"name":"n","check":"isWorkId","repeat":{"text":"d","count":true},"accepted":true}"#,
            #"{"name":"n","check":"workIdFromPath","input":"doc","accepted":true}"#,
            #"{"name":"n","check":"workIdFromPath","input":"doc","accepted":true,"id":7}"#,
        ] {
            XCTAssertThrowsError(try parse(vector), vector)
        }

        let rejected = try XCTUnwrap(parse(#"{"name":"n","check":"isWorkId","input":["doc"],"accepted":false}"#).first)
        XCTAssertNoThrow(try WorkIdRelease.checkOutcome(rejected))
        let accepted = try XCTUnwrap(parse(#"{"name":"n","check":"isWorkId","input":["doc"],"accepted":true}"#).first)
        XCTAssertThrowsError(try WorkIdRelease.checkOutcome(accepted))
    }
}
