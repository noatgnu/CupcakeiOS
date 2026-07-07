import CupcakeNetworking
import Foundation

/// Live cross-device push updates for `TimeKeeper` start/stop/reset, over one shared WebSocket connection.
public actor TimeKeeperNotificationService {
    public enum Event: Sendable, Equatable {
        case started(timeKeeperServerID: Int64, sessionServerID: Int64?, stepServerID: Int64?, startTime: String?)
        case stopped(timeKeeperServerID: Int64, sessionServerID: Int64?, stepServerID: Int64?, duration: Int?)
        case updated(timeKeeperServerID: Int64, sessionServerID: Int64?, stepServerID: Int64?, started: Bool?, duration: Int?)

        /// The session this event's timekeeper belongs to, if the server supplied one.
        public var sessionServerID: Int64? {
            switch self {
            case .started(_, let sessionServerID, _, _),
                 .stopped(_, let sessionServerID, _, _),
                 .updated(_, let sessionServerID, _, _, _):
                return sessionServerID
            }
        }
    }

    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var webSocketTask: URLSessionWebSocketTask?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public func subscribe() -> AsyncStream<Event> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        Task { await self.ensureConnected() }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
        if subscribers.isEmpty {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
    }

    private func ensureConnected() async {
        guard webSocketTask == nil, !subscribers.isEmpty,
              let token = deviceToken(),
              let url = Self.webSocketURL(from: apiClient.baseURL, token: token) else { return }

        var request = URLRequest(url: url)
        request.setValue(Self.originHeader(for: apiClient.baseURL), forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        Task { await self.receiveLoop() }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }
        do {
            while true {
                switch try await task.receive() {
                case .string(let text):
                    broadcast(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { broadcast(text) }
                @unknown default:
                    break
                }
            }
        } catch {
            webSocketTask = nil
            guard !subscribers.isEmpty else { return }
            try? await Task.sleep(for: .seconds(3))
            await ensureConnected()
        }
    }

    private func broadcast(_ text: String) {
        guard let event = Self.parseEvent(from: text) else { return }
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    /// Parses either a JSON number or string, since the consumer sends these IDs as strings.
    private static func int64(from json: [String: Any], key: String) -> Int64? {
        if let number = json[key] as? Int { return Int64(number) }
        if let string = json[key] as? String { return Int64(string) }
        return nil
    }

    private static func int(from json: [String: Any], key: String) -> Int? {
        if let number = json[key] as? Int { return number }
        if let string = json[key] as? String { return Int(string) }
        return nil
    }

    static func parseEvent(from text: String) -> Event? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let timeKeeperServerID = int64(from: json, key: "timekeeperId") else { return nil }
        let sessionServerID = int64(from: json, key: "sessionId")
        let stepServerID = int64(from: json, key: "stepId")

        switch type {
        case "timekeeper.started":
            return .started(
                timeKeeperServerID: timeKeeperServerID, sessionServerID: sessionServerID, stepServerID: stepServerID,
                startTime: json["startTime"] as? String
            )
        case "timekeeper.stopped":
            return .stopped(
                timeKeeperServerID: timeKeeperServerID, sessionServerID: sessionServerID, stepServerID: stepServerID,
                duration: int(from: json, key: "duration")
            )
        case "timekeeper.updated":
            return .updated(
                timeKeeperServerID: timeKeeperServerID, sessionServerID: sessionServerID, stepServerID: stepServerID,
                started: json["started"] as? Bool, duration: int(from: json, key: "duration")
            )
        default:
            return nil
        }
    }

    static func webSocketURL(from apiBaseURL: URL, token: String) -> URL? {
        WebSocketURLBuilder.url(from: apiBaseURL, path: "/ws/ccrv/timekeepers/", token: token)
    }

    static func originHeader(for apiBaseURL: URL) -> String {
        WebSocketURLBuilder.originHeader(for: apiBaseURL)
    }
}
