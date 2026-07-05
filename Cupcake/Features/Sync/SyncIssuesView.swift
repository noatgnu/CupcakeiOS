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
    @Query(sort: \OutboxEntry.sequence) private var entries: [OutboxEntry]
    @Query private var sections: [CachedProtocolSection]
    @Query private var steps: [CachedProtocolStep]
    @Query private var sessions: [CachedSession]
    @Query private var stepReagents: [CachedStepReagent]
    @Query private var reagents: [CachedReagent]
    @Query private var stepAnnotations: [CachedStepAnnotation]
    @Query private var storedReagents: [CachedStoredReagent]
    @Query private var reagentActions: [CachedReagentAction]
    @Query private var instrumentUsages: [CachedInstrumentUsage]

    @State private var isRetrying = false

    /// Most entries carry no field snapshot in their payload (see `EmptyOutboxPayload`'s doc
    /// comment) — look the *current* local record up by `relatedClientID` instead, live off the
    /// same `@Query` the rest of the app reads.
    private func title(for entry: OutboxEntry) -> String {
        guard let operation = OutboxOperationType(rawValue: entry.operationType) else { return entry.operationType }
        switch operation {
        case .createProtocol:
            guard let payload = try? JSONDecoder().decode(CreateProtocolPayload.self, from: entry.payloadJSON) else {
                return "Create protocol"
            }
            return "Create protocol: \(payload.title)"
        case .createSection:
            let name = sections.first(where: { $0.clientID == entry.relatedClientID })?.sectionDescription ?? "Untitled Section"
            return "Create section: \(name)"
        case .createStep:
            let description = steps.first(where: { $0.clientID == entry.relatedClientID })?.stepDescription
            return "Create step: \(description ?? "…")"
        case .createSession:
            let name = sessions.first(where: { $0.clientID == entry.relatedClientID })?.name ?? "Untitled Session"
            return "Create session: \(name)"
        case .createStepReagent:
            guard let stepReagent = stepReagents.first(where: { $0.clientID == entry.relatedClientID }),
                  let reagent = reagents.first(where: { $0.clientID == stepReagent.reagentClientID }) else {
                return "Attach reagent"
            }
            return "Attach reagent: \(reagent.name)"
        case .createTextAnnotation:
            let text = stepAnnotations.first(where: { $0.clientID == entry.relatedClientID })?.annotationText
            return "Add note: \(text ?? "…")"
        case .createStoredReagent:
            let name = storedReagents.first(where: { $0.clientID == entry.relatedClientID })?.reagentName ?? "Reagent"
            return "Add stock: \(name)"
        case .createReagentAction:
            let action = reagentActions.first(where: { $0.clientID == entry.relatedClientID })
            return "Record \(action?.actionType ?? "action"): \(action?.quantity.formatted() ?? "…")"
        case .createInstrumentUsage:
            let usage = instrumentUsages.first(where: { $0.clientID == entry.relatedClientID })
            return "Book instrument: \(usage?.instrumentName ?? "…")"
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
