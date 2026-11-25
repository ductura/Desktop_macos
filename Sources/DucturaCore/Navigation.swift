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

/// Gdje bi se zahtjev učitao (DAN-1544).
public enum NavigationFrame: Equatable {
    case main
    case sub
    /// `target=_blank` ili `window.open` (WebKit daje `targetFrame == nil`).
    case newWindow
}

/// Što web prikaz radi sa zahtjevom (DAN-1544).
public enum NavigationPolicy: Equatable {
    case allow
    case cancel
    /// Ne učitava se u ljusci; adresa (točno tekst koji je pravilo provjerilo) ide u sustavni preglednik.
    case cancelAndOpen(String)
}

extension Navigation {
    /// Odluka za svaki `decidePolicyFor` web prikaza: prvo `decide`, pa okvir i vrsta navigacije.
    /// Host s popisa učitava se samo u postojećem okviru (ljuska ne otvara nove prozore). U preglednik
    /// ide samo klik na poveznicu u glavnom okviru ili novom prozoru; skripta, redirect, obrazac ili
    /// podokvir prema drugom hostu se samo odbijaju, da stranica ne može sama otvarati preglednik.
    public static func policy(url: String?, hosts: String?, frame: NavigationFrame, linkActivated: Bool) -> NavigationPolicy {
        switch decide(url: url, hosts: hosts) {
        case .stay: return frame == .newWindow ? .cancel : .allow
        case .browser(let target): return frame != .sub && linkActivated ? .cancelAndOpen(target) : .cancel
        case .refuse: return .cancel
        }
    }
}
