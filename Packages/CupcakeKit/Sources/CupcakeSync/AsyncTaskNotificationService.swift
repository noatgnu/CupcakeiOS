import CupcakeNetworking
import Foundation

public actor AsyncTaskNotificationService {
    public struct Event: Sendable, Equatable {
        public let taskID: String
        public let taskType: String?
        public let status: String
        public let progressPercentage: Double?
        public let progressDescription: String?
        public let errorMessage: String?
        public let downloadURL: String?
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
        let subscribeMessage = #"{"type":"subscribe","subscription_type":"async_task_updates"}"#
        try? await task.send(.string(subscribeMessage))
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

    static func parseEvent(from text: String) -> Event? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "async_task.update",
              let taskID = json["task_id"] as? String,
              let status = json["status"] as? String else { return nil }
        return Event(
            taskID: taskID,
            taskType: json["task_type"] as? String,
            status: status,
            progressPercentage: json["progress_percentage"] as? Double,
            progressDescription: json["progress_description"] as? String,
            errorMessage: json["error_message"] as? String,
            downloadURL: json["download_url"] as? String
        )
    }

    static func webSocketURL(from apiBaseURL: URL, token: String) -> URL? {
        WebSocketURLBuilder.url(from: apiBaseURL, path: "/ws/ccc/notifications/", token: token)
    }

    static func originHeader(for apiBaseURL: URL) -> String {
        WebSocketURLBuilder.originHeader(for: apiBaseURL)
    }
}
