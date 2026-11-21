import XCTest
@testable import DucturaCore

final class ManifestVectorsTests: XCTestCase {
    private let expected: [String: (arm64: UpdateOffer?, x64: UpdateOffer?)] = [
        "ready": (
            UpdateOffer(version: "1.0.0",
                        url: "https://preuzimanje.example.invalid/ductura/1.0.0/ductura-macos-arm64.dmg",
                        sha256: String(repeating: "a", count: 64)),
            UpdateOffer(version: "1.0.0",
                        url: "/preuzimanje/ductura/1.0.0/ductura-macos-x64.dmg",
                        sha256: String(repeating: "b", count: 64))
        ),
        "ready-empty": (nil, nil),
        "unavailable": (nil, nil),
    ]

    func testSvakiManifestVektorDajeOcekivaniIshodZaObjeArhitekture() throws {
        let vectors = try TestFakesRelease.vectors(for: "downloads.manifest.get", in: TestFakesRelease.vectorJSON.get())
        XCTAssertEqual(vectors.map(\.name).sorted(), expected.keys.sorted())
        for vector in vectors {
            let outcomes = try XCTUnwrap(expected[vector.name], vector.name)
            for architecture in UpdateArchitecture.allCases {
                let offer = UpdateOffer.decide(status: vector.status, body: vector.body, installedVersion: "0.9.0",
                                               architecture: architecture)
                XCTAssertEqual(offer, architecture == .arm64 ? outcomes.arm64 : outcomes.x64,
                               "\(vector.name) / \(architecture.rawValue)")
            }
        }
    }
}
