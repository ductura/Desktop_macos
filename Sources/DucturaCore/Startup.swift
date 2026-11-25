import Foundation

/// Sadržaj prozora (DAN-957): web prikaz samo za provjerenu adresu, inače poruka.
public enum WindowContent: Equatable {
    case web(URL)
    case message(String)
}

/// Što aplikacija radi s adresom iz paketa (DAN-883). `main.swift` samo primjenjuje ove rezultate.
public enum Startup {
    /// Tekst umjesto web prikaza kad adresa iz paketa ne prolazi provjeru.
    public static let invalidAddressText = "Adresa Ducture u ovom paketu nije ispravna."

    /// Ishod `--smoke`: paket s neispravnom adresom vraća 1 i ne piše potvrdu.
    public static func smoke(web: WebAddress?, version: String) -> (exitCode: Int32, line: String?) {
        web == nil ? (1, nil) : (0, "Ductura OK \(version)")
    }

    /// Adresa za otvaranje ili `nil` (fail closed): neprovjerena adresa se nikad ne otvara.
    public static func linkURL(options: LaunchOptions, web: WebAddress?) -> URL? {
        guard let web else { return nil }
        return WorkId.documentURL(web: web, id: options.openDocumentId) ?? URL(string: web.url)
    }

    /// Sadržaj prozora: WKWebView s adresom iz `linkURL` ili poruka (fail closed).
    public static func windowContent(options: LaunchOptions, web: WebAddress?) -> WindowContent {
        linkURL(options: options, web: web).map(WindowContent.web) ?? .message(invalidAddressText)
    }

    /// Sadržaj prozora nakon provjere verzije (DAN-1545): klijent koji mora nadograditi nikad ne otvara web.
    public static func windowContent(options: LaunchOptions, web: WebAddress?, decision: ClientVersionDecision) -> WindowContent {
        let link = linkURL(options: options, web: web)
        guard let url = ClientVersion.webURL(decision, link: link) else {
            return .message(link == nil ? invalidAddressText : ClientVersion.updateText)
        }
        return .web(url)
    }

    /// Redak `--smoke-window` iz stvarnog sadržaja prozora: `web <adresa>` samo za točno jedan
    /// web prikaz bez poruke, `message` samo za poruku bez web prikaza, inače `error`.
    public static func windowReport(webViews: [URL?], messages: [String]) -> String {
        if webViews.count == 1, let url = webViews[0], messages.isEmpty { return "Ductura window web \(url.absoluteString)" }
        if webViews.isEmpty, (messages == [invalidAddressText] || messages == [ClientVersion.updateText]) { return "Ductura window message" }
        return "Ductura window error"
    }
}
