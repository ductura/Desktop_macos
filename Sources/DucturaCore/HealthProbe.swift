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

    /// Total deadline (not inactivity, which is all `timeoutInterval` limits): after `deadline` seconds
    /// the call is cancelled and the answer is `unavailable`.
    public static func read(web: WebAddress, clientVersion: String, deadline: TimeInterval = timeout,
                            send: @escaping (URLRequest) async throws -> (Data, URLResponse)) async -> HealthReading {
        guard let request = request(web: web, clientVersion: clientVersion) else { return .unavailable }
        let result: (Data, URLResponse)? = await withTaskGroup(of: (Data, URLResponse)?.self) { group in
            group.addTask { try? await send(request) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let result else { return .unavailable }
        return reading(data: result.0, response: result.1)
    }

    /// Production transport: a redirect is refused, so the version header never follows one to another URL
    /// (the 3xx answer is then not a 200 and counts as `unavailable`).
    public static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request, delegate: NoRedirectDelegate())
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
