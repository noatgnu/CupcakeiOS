import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

struct ProtocolListView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedProtocol.protocolTitle) private var protocols: [CachedProtocol]
    @Query private var outboxEntries: [OutboxEntry]

    @State private var selectedProtocolID: UUID?
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingNewProtocolSheet = false
    @State private var isShowingSyncIssues = false

    /// A protocol authored by this app that hasn't reached the server yet, while signed in, is
    /// either queued in the outbox (will sync automatically on reconnect) or the sync attempt
    /// itself failed outright — either way, distinct from a *permanently* local record in
    /// standalone mode, where there's no server to sync to at all.
    private func pendingSyncLabel(for protocolModel: CachedProtocol) -> String? {
        guard protocolModel.serverID == nil else { return nil }
        guard protocolModel.isLocallyAuthored else { return nil }
        return appSession.isAuthenticated ? "Pending sync" : "Local only"
    }

    var body: some View {
        NavigationSplitView {
            List(protocols, selection: $selectedProtocolID) { protocolModel in
                VStack(alignment: .leading) {
                    Text(protocolModel.protocolTitle)
                    if let label = pendingSyncLabel(for: protocolModel) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(protocolModel.clientID)
            }
            .navigationTitle("Protocols")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewProtocolSheet = true
                    } label: {
                        Label("New Protocol", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newProtocolButton")
                }
                if appSession.isAuthenticated {
                    ToolbarItem {
                        Button {
                            isShowingSyncIssues = true
                        } label: {
                            Label(outboxEntries.isEmpty ? "Sync Issues" : "Sync Issues (\(outboxEntries.count))", systemImage: outboxEntries.isEmpty ? "checkmark.icloud" : "exclamationmark.icloud")
                        }
                        .accessibilityIdentifier("syncIssuesButton")
                    }
                    ToolbarItem {
                        Button {
                            Task { await sync() }
                        } label: {
                            if isSyncing {
                                ProgressView()
                            } else {
                                Label("Sync", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isSyncing)
                    }
                    ToolbarItem {
                        Button("Sign Out") {
                            Task { await appSession.signOut() }
                        }
                    }
                } else if appSession.isStandalone {
                    ToolbarItem {
                        Button("Exit Offline Mode") {
                            appSession.exitStandalone()
                        }
                    }
                }
            }
            .task { await sync() }
            .sheet(isPresented: $isShowingNewProtocolSheet) {
                NewProtocolView()
            }
            .sheet(isPresented: $isShowingSyncIssues) {
                SyncIssuesView()
            }
            .alert("Sync failed", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        } detail: {
            // `.navigationDestination` inside a NavigationSplitView's detail column needs its
            // own explicit NavigationStack to register pushes — without one, ProtocolDetailView's
            // "start session" push silently does nothing (confirmed via XCUITest: the button tap
            // registers, but the detail column never navigates to SessionDetailView).
            NavigationStack {
                if let selectedProtocolID, let protocolModel = protocols.first(where: { $0.clientID == selectedProtocolID }) {
                    ProtocolDetailView(protocolModel: protocolModel)
                } else {
                    Text("Select a protocol")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sync() async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        isSyncing = true
        defer { isSyncing = false }
        await appSession.replayOutbox()
        do {
            try await services.protocolSync.refetchAll()
            try await services.stepReagentSync.refetchAll()
            try await services.inventorySync.refetchStorageObjects()
            try await services.inventorySync.refetchReagents()
            try await services.inventorySync.refetchStoredReagents()
            try await services.inventorySync.refetchReagentActions()
            try await services.instrumentSync.refetchInstruments()
            try await services.instrumentSync.refetchInstrumentUsage()
            try await services.projectSync.refetchAll()
            try await services.instrumentJobSync.refetchAll()
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}
