import Foundation

/// Client version in a request header (DAN-1545). Same placement rule as `AuthHeader`: only on
/// `https://<web host>/api/v1/…` of the checked web address, never on an HTML page. Fail closed:
/// a version that is not strict `major.minor.patch` gives no header at all.
/// The header name is an assumption (no server contract names it yet); see the PR.
public enum ClientVersionHeader {
    public static let headerName = "X-Ductura-Client-Version"

    public static func headers(version: String, url: String?, web: WebAddress?) -> [String: String] {
        guard let web, let url, ClientVersion.parse(version) != nil,
              AuthHeader.isApiOnOrigin(url: url, web: web) else { return [:] }
        return [headerName: version]
    }
}
