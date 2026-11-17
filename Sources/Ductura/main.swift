import Foundation
import DucturaCore
#if canImport(AppKit)
import AppKit
import WebKit
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
        // Fail closed: without a checked address there is no WKWebView, only the message (DAN-957).
        let view: NSView
        switch Startup.windowContent(options: options, web: web) {
        case .web(let url):
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            webView.load(URLRequest(url: url))
            requested = url
            view = webView
        case .message(let text):
            let label = NSTextField(labelWithString: text)
            label.frame = NSRect(x: 24, y: 560, width: 480, height: 32)
            view = NSView()
            view.addSubview(label)
        }
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let out = options.smokeWindowOutput {
            DispatchQueue.main.async { self.reportWindow(to: out) }
        }
    }
    var requested: URL?
    /// Functional test: report what the window really contains, then quit.
    func reportWindow(to out: String) {
        var views: [NSView] = window.contentView.map { [$0] } ?? []
        var webViews: [URL?] = [], messages: [String] = []
        while let v = views.popLast() {
            // WebKit's own subviews are not ours to count.
            if let w = v as? WKWebView { webViews.append(w.url ?? requested); continue }
            if let t = v as? NSTextField { messages.append(t.stringValue) }
            views += v.subviews
        }
        let line = Startup.windowReport(webViews: webViews, messages: messages)
        try? (line + "\n" + Bundle.main.bundlePath + "\n").write(toFile: out, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#endif
