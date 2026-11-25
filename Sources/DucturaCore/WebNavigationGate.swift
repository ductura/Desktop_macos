#if canImport(WebKit)
import Foundation
import WebKit

/// Delegat navigacije web prikaza ljuske (DAN-1544): svaki zahtjev prolazi kroz `Navigation.policy`
/// s popisom hostova iz paketa. Odbijeno odredište se ne učitava. `WKWebView.navigationDelegate`
/// je slaba referenca, pa ga vlasnik prozora mora držati.
public final class WebNavigationGate: NSObject, WKNavigationDelegate {
    let hosts: String?
    let openExternally: (URL) -> Void
    let allowedMainFrame: (WKWebView, URL) -> Void

    /// - Parameters:
    ///   - hosts: `DucturaWebHosts` iz `Info.plist` (loš ili `nil` odbija sve).
    ///   - openExternally: otvaranje u sustavnom pregledniku.
    ///   - allowedMainFrame: dopuštena navigacija glavnog okvira (izvještaj `--smoke-window`).
    public init(hosts: String?, openExternally: @escaping (URL) -> Void,
                allowedMainFrame: @escaping (WKWebView, URL) -> Void = { _, _ in }) {
        self.hosts = hosts
        self.openExternally = openExternally
        self.allowedMainFrame = allowedMainFrame
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let frame: NavigationFrame
        switch navigationAction.targetFrame?.isMainFrame {
        case nil: frame = .newWindow
        case true?: frame = .main
        case false?: frame = .sub
        }
        let url = navigationAction.request.url
        switch Navigation.policy(url: url?.absoluteString, hosts: hosts, frame: frame,
                                 linkActivated: navigationAction.navigationType == .linkActivated) {
        case .allow:
            decisionHandler(.allow)
            if frame == .main, let url { allowedMainFrame(webView, url) }
        case .cancel:
            decisionHandler(.cancel)
        case .cancelAndOpen(let target):
            decisionHandler(.cancel)
            if let external = URL(string: target) { openExternally(external) }
        }
    }
}
#endif
