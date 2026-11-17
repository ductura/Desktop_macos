import Foundation

/// Odluka o navigaciji u WKWebView ljuske (DAN-961).
public enum NavigationDecision: Equatable {
    /// Host s popisa: navigacija ostaje u ljusci.
    case stay
    /// Drugi `https` host: adresa (točno ulazni tekst) ide u sustavni preglednik.
    case browser(String)
    /// Sve ostalo se odbija.
    case refuse
}

/// Pravilo za `decidePolicyFor` (adapter predaje `request.url?.absoluteString` i `DucturaWebHosts`).
/// Izričita pravila nad tekstom, kao `WebAddress`, jer se `URL` razlikuje po platformama.
public enum Navigation {
    /// Znakovi u rasponu 0x21–0x7E koji nisu dopušteni nigdje u URI-ju (RFC 3986).
    static let forbidden: Set<UInt8> = Set("{}|^\"<>\\`".utf8)

    /// Fail closed: loš popis hostova, shema osim `https://`, znak izvan dopuštenog ASCII-ja ili
    /// autoritet koji nije čisto ime hosta (port, korisnik, IP, velika slova) daju `.refuse`.
    /// Put, upit i fragment hosta s popisa se ne provjeravaju (isto podrijetlo).
    public static func decide(url: String?, hosts: String?) -> NavigationDecision {
        guard let allowed = WebAddress.hostList(hosts), let url,
              url.utf8.allSatisfy({ (0x21...0x7E).contains($0) && !forbidden.contains($0) }),
              url.hasPrefix("https://") else { return .refuse }
        let rest = url.dropFirst("https://".count)
        let host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard WebAddress.isHostName(host) else { return .refuse }
        return allowed.contains(String(host)) ? .stay : .browser(url)
    }
}
