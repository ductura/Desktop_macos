import Foundation
import DucturaCore
#if canImport(AppKit)
import AppKit
#endif

let options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
// Web address from the bundle's Info.plist (DAN-883); nil when it fails the check.
let web = WebAddress.fromInfo(Bundle.main.infoDictionary)

if options.smoke {
    // A package with an invalid web address must not pass the functional test.
    let (code, line) = Startup.smoke(web: web, version: version)
    if let line {
        if let out = options.smokeOutput { try? line.write(toFile: out, atomically: true, encoding: .utf8) }
        else { print(line) }
    }
    exit(code)
}

#if canImport(AppKit)
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = Packaging.productName
        // Fail closed: without a checked address there is no button, only the message.
        let view: NSView = Startup.linkURL(options: options, web: web) == nil
            ? NSTextField(labelWithString: Startup.invalidAddressText)
            : NSButton(title: "Otvori Ducturu", target: self, action: #selector(openWeb))
        view.frame = NSRect(x: 24, y: 560, width: 480, height: 32)
        window.contentView?.addSubview(view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Sljedeći korak: ugraditi editor (WKWebView) umjesto gumba.
    }
    @objc func openWeb() {
        // ID ulazi u URL samo kodiran i samo ako prolazi pravilo ugovora (WorkId).
        guard let url = Startup.linkURL(options: options, web: web) else { return }
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
