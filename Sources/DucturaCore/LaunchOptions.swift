import Foundation

/// Argumenti pokretanja. `--smoke-out <putanja>` služi funkcionalnom testu.
public struct LaunchOptions: Equatable {
    public var smoke = false
    public var smokeOutput: String?
    public var openDocumentId: String?

    public init(smoke: Bool = false, smokeOutput: String? = nil, openDocumentId: String? = nil) {
        self.smoke = smoke; self.smokeOutput = smokeOutput; self.openDocumentId = openDocumentId
    }

    public static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--smoke" { o.smoke = true }
            else if a == "--smoke-out", i + 1 < args.count { o.smoke = true; i += 1; o.smokeOutput = args[i] }
            else if a.lowercased().hasPrefix("ductura://doc/") {
                let id = String(a.dropFirst("ductura://doc/".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                o.openDocumentId = id.isEmpty ? nil : id
            }
            i += 1
        }
        return o
    }
}
