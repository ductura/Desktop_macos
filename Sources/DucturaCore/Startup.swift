import Foundation

/// Što aplikacija radi s adresom iz paketa (DAN-883). `main.swift` samo primjenjuje ove rezultate.
public enum Startup {
    /// Tekst umjesto gumba kad adresa iz paketa ne prolazi provjeru.
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
}
