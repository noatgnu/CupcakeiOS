import Foundation

enum WebSocketURLBuilder {
    static func url(from apiBaseURL: URL, path: String, token: String) -> URL? {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = path
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    static func originHeader(for apiBaseURL: URL) -> String {
        guard let scheme = apiBaseURL.scheme, let host = apiBaseURL.host else { return "" }
        let httpScheme = scheme == "wss" || scheme == "https" ? "https" : "http"
        guard let port = apiBaseURL.port else { return "\(httpScheme)://\(host)" }
        return "\(httpScheme)://\(host):\(port)"
    }
}
