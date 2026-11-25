#if canImport(WebKit)
import Foundation
import WebKit

/// Delegat navigacije web prikaza ljuske (DAN-1544): svaki zahtjev prolazi kroz `Navigation.policy`
/// s popisom hostova iz paketa. Odbijeno odredište se ne učitava. `WKWebView.navigationDelegate`
/// je slaba referenca, pa ga vlasnik prozora mora držati.
public final class WebNavigationGate: NSObject, WKNavigationDelegate {
    let hosts: String?
    let openExternally: (URL) -> Void
    let allowedMainFrame: (ObjectIdentifier, URL) -> Void

    /// - Parameters:
    ///   - hosts: `DucturaWebHosts` iz `Info.plist` (loš ili `nil` odbija sve).
    ///   - openExternally: otvaranje u sustavnom pregledniku.
    ///   - allowedMainFrame: dopuštena navigacija glavnog okvira, po web prikazu (izvještaj `--smoke-window`).
    public init(hosts: String?, openExternally: @escaping (URL) -> Void,
                allowedMainFrame: @escaping (ObjectIdentifier, URL) -> Void = { _, _ in }) {
        self.hosts = hosts
        self.openExternally = openExternally
        self.allowedMainFrame = allowedMainFrame
    }

    /// WebKit pita za svaki zahtjev (i za svaki redirect); odgovor je uvijek točno jedan.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(decide(url: navigationAction.request.url, isMainFrame: navigationAction.targetFrame?.isMainFrame,
                               navigationType: navigationAction.navigationType, view: ObjectIdentifier(webView)))
    }

    /// Odluka delegata iz polja koja WebKit daje (`targetFrame == nil` je novi prozor). Odvojeno od
    /// `WKNavigationAction`, jer se WebKitovi objekti ne mogu stvoriti izvan WebKita (test).
    func decide(url: URL?, isMainFrame: Bool?, navigationType: WKNavigationType, view: ObjectIdentifier) -> WKNavigationActionPolicy {
        let frame = isMainFrame.map { $0 ? NavigationFrame.main : .sub } ?? .newWindow
        switch Navigation.policy(url: url?.absoluteString, hosts: hosts, frame: frame,
                                 linkActivated: navigationType == .linkActivated) {
        case .allow:
            if frame == .main, let url { allowedMainFrame(view, url) }
            return .allow
        case .cancel:
            return .cancel
        case .cancelAndOpen(let target):
            if let external = URL(string: target) { openExternally(external) }
            return .cancel
        }
    }
}
#endif
