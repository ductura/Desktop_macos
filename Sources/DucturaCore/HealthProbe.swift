import Foundation

/// Launch call of `health` (DAN-1545) through the generated contract client. No retries.
/// The transport is injected, so tests need no network.
public enum HealthProbe {
    public static let timeout: TimeInterval = 5

    /// `GET <origin>/api/v1/health` with the client version header, or nil without a usable origin.
    public static func request(web: WebAddress, clientVersion: String) -> URLRequest? {
        guard let origin = AuthHeader.origin(of: web), let base = URL(string: origin + "/") else { return nil }
        var request = PlatformHealthGet.request(base: base)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let headers = ClientVersionHeader.headers(version: clientVersion, url: request.url?.absoluteString, web: web)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// An answer is status 200, a JSON content type and a body that decodes by the contract.
    /// Anything else (other status, HTML, wrong field type, no response) is `unavailable`.
    public static func reading(data: Data, response: URLResponse?) -> HealthReading {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let type = http.value(forHTTPHeaderField: "Content-Type"),
              type.lowercased().hasPrefix("application/json"),
              let body = try? JSONDecoder().decode(PlatformHealthGetResponse.self, from: data)
        else { return .unavailable }
        return .answered(status: body.status, minClientVersion: body.minClientVersion)
    }

    public static func read(web: WebAddress, clientVersion: String,
                            send: (URLRequest) async throws -> (Data, URLResponse)) async -> HealthReading {
        guard let request = request(web: web, clientVersion: clientVersion),
              let result = try? await send(request) else { return .unavailable }
        return reading(data: result.0, response: result.1)
    }
}
