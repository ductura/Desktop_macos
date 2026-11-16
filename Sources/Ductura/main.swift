import Foundation
import DucturaCore
#if canImport(AppKit)
import AppKit
#endif

let options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

if options.smoke {
    let line = "Ductura OK \(version)"
    if let out = options.smokeOutput { try? line.write(toFile: out, atomically: true, encoding: .utf8) }
    else { print(line) }
    exit(0)
}

#if canImport(AppKit)
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = Packaging.productName
        let button = NSButton(title: "Otvori Ducturu", target: self, action: #selector(openWeb))
        button.frame = NSRect(x: 24, y: 560, width: 180, height: 32)
        window.contentView?.addSubview(button)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Sljedeći korak: ugraditi editor (WKWebView) umjesto gumba.
    }
    @objc func openWeb() {
        // ID ulazi u URL samo kodiran i samo ako prolazi pravilo ugovora (WorkId).
        let url = WorkId.documentURL(base: Packaging.webURL, id: options.openDocumentId)
            ?? URL(string: Packaging.webURL)!
        NSWorkspace.shared.open(url)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#endif
