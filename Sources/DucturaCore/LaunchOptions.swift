import Foundation

/// Argumenti pokretanja. `--smoke-out <putanja>` služi funkcionalnom testu.
public struct LaunchOptions: Equatable {
    public var smoke = false
    public var smokeOutput: String?
    public var openDocumentId: String?
    /// `--smoke-window <putanja>`: prozor se gradi, a u datoteku ide `Startup.windowReport` (DAN-957).
    public var smokeWindowOutput: String?

    public init(smoke: Bool = false, smokeOutput: String? = nil, openDocumentId: String? = nil,
                smokeWindowOutput: String? = nil) {
        self.smoke = smoke; self.smokeOutput = smokeOutput; self.openDocumentId = openDocumentId
        self.smokeWindowOutput = smokeWindowOutput
    }

    public static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--smoke" { o.smoke = true }
            else if a == "--smoke-out", i + 1 < args.count { o.smoke = true; i += 1; o.smokeOutput = args[i] }
            else if a == "--smoke-window", i + 1 < args.count, isPath(args[i + 1]) { i += 1; o.smokeWindowOutput = args[i] }
            else if let rest = linkRest(a) { o.openDocumentId = documentId(linkRest: rest) }
            i += 1
        }
        return o
    }

    /// Putanja za `--smoke-window`: ni zastavica ni poveznica (`--smoke` ima prednost i prozor se ne gradi).
    static func isPath(_ arg: String) -> Bool {
        !arg.isEmpty && !arg.hasPrefix("-") && linkRest(arg) == nil
    }

    /// Ostatak iza `ductura://doc/` (prefiks ASCII bez obzira na velika slova) ili `nil`.
    static func linkRest(_ arg: String) -> Substring.UnicodeScalarView? {
        let prefix = "ductura://doc/".unicodeScalars
        let scalars = Substring(arg).unicodeScalars
        guard scalars.count >= prefix.count, zip(scalars, prefix).allSatisfy({ (a, p) in
            (0x41...0x5A).contains(a.value) ? a.value + 0x20 == p.value : a == p
        }) else { return nil }
        return scalars.dropFirst(prefix.count)
    }

    /// ID iz ostatka poveznice: jedna završna `/` se skida, a sirovi `/`, `?`
    /// ili `#` znače da to nije jedan segment. Pravilo je `WorkId.fromPathSegment`.
    static func documentId(linkRest: Substring.UnicodeScalarView) -> String? {
        var rest = linkRest
        if rest.last == "/" { rest = rest.dropLast() }
        if rest.contains(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { return nil }
        return WorkId.fromPathSegment(String(rest))
    }
}
