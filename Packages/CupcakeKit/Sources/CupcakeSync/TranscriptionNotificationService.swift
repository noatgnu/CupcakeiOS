import CupcakeNetworking
import Foundation

/// Live push updates for server-side transcription, over one shared WebSocket connection.
public actor TranscriptionNotificationService {
    public enum Event: Sendable, Equatable {
        case started(annotationServerID: Int64)
        case completed(annotationServerID: Int64)
        case failed(annotationServerID: Int64, error: String)
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

    static func parseEvent(from text: String) -> Event? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let rawAnnotationID = json["annotation_id"] as? Int else { return nil }
        let annotationServerID = Int64(rawAnnotationID)

        switch type {
        case "transcription.started":
            return .started(annotationServerID: annotationServerID)
        case "transcription.completed":
            return .completed(annotationServerID: annotationServerID)
        case "transcription.failed":
            return .failed(annotationServerID: annotationServerID, error: json["error"] as? String ?? "")
        default:
            return nil
        }
    }

    static func webSocketURL(from apiBaseURL: URL, token: String) -> URL? {
        WebSocketURLBuilder.url(from: apiBaseURL, path: "/ws/ccc/notifications/", token: token)
    }

    static func originHeader(for apiBaseURL: URL) -> String {
        WebSocketURLBuilder.originHeader(for: apiBaseURL)
    }
}
