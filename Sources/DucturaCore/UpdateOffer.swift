import Foundation

/// Architecture names from the downloads manifest.
public enum UpdateArchitecture: String, CaseIterable {
    case arm64, x64
}

/// A newer macOS package offered by downloads.manifest.get (S-1H.5).
public struct UpdateOffer: Equatable {
    public let version: String
    public let url: String
    public let sha256: String

    /// Validates the entire response before returning the matching offer.
    /// The address is returned as the decoded string, without resolving or normalizing it.
    public static func decide(
        status: Int, body: Data?, installedVersion: String?, architecture: UpdateArchitecture
    ) -> UpdateOffer? {
        guard status == 200, let body, let installedVersion, let installed = versionParts(installedVersion),
              case let .object(root)? = StrictJSON.parse(body), root.count == 1,
              case let .array(rows)? = root["packages"], rows.count <= 4 else { return nil }

        var pairs = Set<String>()
        var offer: UpdateOffer?
        for row in rows {
            guard case let .object(fields) = row, fields.count == 5,
                  case let .string(system)? = fields["system"], system == "macos" || system == "windows",
                  case let .string(arch)? = fields["architecture"], UpdateArchitecture(rawValue: arch) != nil,
                  case let .string(version)? = fields["version"], let offered = versionParts(version),
                  case let .string(url)? = fields["url"], url.utf16.count <= 2048,
                  urlPattern.firstMatch(in: url, range: NSRange(url.startIndex..<url.endIndex, in: url)) != nil,
                  case let .string(sha256)? = fields["sha256"], sha256.utf8.count == 64,
                  sha256.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }),
                  pairs.insert("\(system)/\(arch)").inserted else { return nil }
            if system == "macos", arch == architecture.rawValue,
               installed.lexicographicallyPrecedes(offered, by: componentPrecedes) {
                offer = UpdateOffer(version: version, url: url, sha256: sha256)
            }
        }
        return offer
    }

    private static func versionParts(_ version: String) -> [[UInt8]]? {
        let parts = version.utf8.split(separator: 0x2E, omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && (part.count == 1 || part.first != 0x30)
                && part.allSatisfy { (0x30...0x39).contains($0) }
        }) else { return nil }
        return parts.map(Array.init)
    }

    // Valid components have no leading zero. Compare by length, then by digit, without an integer limit.
    private static func componentPrecedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs.count == rhs.count ? lhs.lexicographicallyPrecedes(rhs) : lhs.count < rhs.count
    }

    // URL pattern from downloads.manifest.get, also used by Windows UpdateOffer.
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"\A(?![\s\S]*(?:%2[eE]|%00|/\.\.?(?:[/?]|\z)))(?:https://(?=[a-z0-9.-]{1,253}/)(?!(?:[a-z0-9.-]*\.)?(?:localhost|local|internal|home\.arpa)/)(?![a-z0-9]{2}--)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.(?![a-z0-9]{2}--)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\.(?![a-z0-9]{2}--)[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?)?/(?![/?])(?:[A-Za-z0-9._~!$&'()*+,;=:@/?-]|%[0-9A-Fa-f]{2})+\z"#
    )
}
