import Foundation

public enum Packaging {
    public static let productName = "Ductura"
    public static let bundleIdentifier = "org.ductura.desktop"
    public static let webURL = "https://ductura.org"

    /// Naziv paketa koji nudi preloader.
    public static let dmgFileName = "Ductura-macOS.dmg"

    /// Putanja aplikacije nakon instalacije.
    public static func installedAppPath(applicationsFolder: String = "/Applications") -> String {
        (applicationsFolder as NSString).appendingPathComponent("\(productName).app")
    }

    /// Je li ponuđena verzija novija od instalirane (semver, samo brojevi).
    public static func isNewer(_ offered: String, than installed: String) -> Bool {
        guard let o = parts(offered), let i = parts(installed) else { return false }
        return o.lexicographicallyPrecedes(i) == false && o != i
    }

    static func parts(_ v: String) -> [Int]? {
        let p = v.split(separator: ".").map { Int($0) }
        guard !p.isEmpty, p.allSatisfy({ $0 != nil }) else { return nil }
        var nums = p.compactMap { $0 }
        while nums.count < 3 { nums.append(0) }
        return nums
    }
}
