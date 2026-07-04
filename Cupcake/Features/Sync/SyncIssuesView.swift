import CupcakeModels
import SwiftData
import SwiftUI

/// Lists everything queued in the outbox — entries still pending a retry (usually just waiting
/// for connectivity, replayed automatically by `AppSession`'s `NWPathMonitor` hook) and entries
/// that failed for a real, non-connectivity reason (`OutboxEntry.status == .failed`) and won't
/// retry again on their own. A manual "Retry Now" covers the case where the device *thinks* it
/// has connectivity but the specific host is still unreachable (captive portal, VPN, etc.).
struct SyncIssuesView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OutboxEntry.createdAt) private var entries: [OutboxEntry]

    @State private var isRetrying = false

    private func title(for entry: OutboxEntry) -> String {
        guard let operation = OutboxOperationType(rawValue: entry.operationType) else { return entry.operationType }
        switch operation {
        case .createProtocol:
            guard let payload = try? JSONDecoder().decode(CreateProtocolPayload.self, from: entry.payloadJSON) else {
                return "Create protocol"
            }
            return "Create protocol: \(payload.title)"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing Pending",
                        systemImage: "checkmark.icloud",
                        description: Text("Everything you've created has synced to the server.")
                    )
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(for: entry))
                            HStack(spacing: 4) {
                                Text(entry.status == OutboxEntryStatus.failed.rawValue ? "Failed" : "Waiting to sync")
                                if entry.retryCount > 0 {
                                    Text("· \(entry.retryCount) retr\(entry.retryCount == 1 ? "y" : "ies")")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let lastError = entry.lastError {
                                Text(lastError)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sync Issues")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !entries.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                isRetrying = true
                                await appSession.replayOutbox()
                                isRetrying = false
                            }
                        } label: {
                            if isRetrying {
                                ProgressView()
                            } else {
                                Text("Retry Now")
                            }
                        }
                        .disabled(isRetrying)
                        .accessibilityIdentifier("retrySyncButton")
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 400)
    }
}
