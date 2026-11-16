import Foundation

/// Provjerena adresa weba iz konfiguracije paketa (DAN-883): ključevi `DucturaWebURL` i
/// `DucturaWebHosts` u `Info.plist` aplikacije. Nastaje samo kroz `make`, pa je svaka
/// instanca prošla provjeru. Pravila su ista kao na Windowsu (ductura/desktop-windows#4).
public struct WebAddress: Equatable {
    public static let urlKey = "DucturaWebURL"
    public static let hostsKey = "DucturaWebHosts"

    /// `https://<host s popisa>/<put>/`, bez upita, fragmenta, porta i korisnika.
    public let url: String

    /// Adresa iz rječnika `Info.plist` ili `nil` ako ključ nedostaje, nije tekst ili ne prolazi provjeru.
    public static func fromInfo(_ info: [String: Any]?) -> WebAddress? {
        make(url: info?[urlKey] as? String, hosts: info?[hostsKey] as? String)
    }

    /// Prolazi samo tekst od ASCII znakova 0x21–0x7E s prefiksom točno `https://`, hostom koji je
    /// ordinalno jedan od hostova s popisa (odvojenih s `;`) i putem koji počinje i završava s `/`,
    /// sa segmentima samo od RFC 3986 unreserved znakova, bez `.` i `..`. Izričita pravila umjesto
    /// `URL`/`URLComponents`, jer se ti parseri razlikuju po platformama.
    public static func make(url: String?, hosts: String?) -> WebAddress? {
        guard let allowed = hostList(hosts), let url, url.utf8.allSatisfy({ (0x21...0x7E).contains($0) }),
              url.hasPrefix("https://") else { return nil }
        let rest = url.dropFirst("https://".count)
        guard let slash = rest.firstIndex(of: "/"), allowed.contains(String(rest[..<slash])) else { return nil }
        let path = rest[slash...]
        guard path.hasSuffix("/") else { return nil }
        let segments = path.dropFirst().dropLast().split(separator: "/", omittingEmptySubsequences: false)
        if path.count > 1, !segments.allSatisfy(isSegment) { return nil }
        return WebAddress(url: url)
    }

    static func isSegment(_ s: Substring) -> Bool {
        !s.isEmpty && s != "." && s != ".." && s.utf8.allSatisfy { b in
            (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b)
                || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E
        }
    }

    /// Hostovi s popisa; jedan loš ili prazan unos odbija cijeli popis (fail closed).
    static func hostList(_ hosts: String?) -> Set<String>? {
        guard let hosts else { return nil }
        let entries = hosts.split(separator: ";", omittingEmptySubsequences: false)
        guard entries.allSatisfy(isHostName) else { return nil }
        return Set(entries.map(String.init))
    }

    /// LDH ime s malim slovima: barem dvije oznake od 1 do 63 znaka, bez rubne `-`, a zadnja
    /// oznaka počinje slovom. Time IPv4 adresa nikad nije ime hosta, ni u obliku koji WHATWG
    /// parser čita kao broj (završna oznaka od znamenki, `0x…` ili `0…`).
    static func isHostName(_ host: Substring) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let first = labels.last?.utf8.first, (0x61...0x7A).contains(first)
        else { return false }
        return labels.allSatisfy { l in
            (1...63).contains(l.utf8.count) && l.first != "-" && l.last != "-"
                && l.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D }
        }
    }
}
