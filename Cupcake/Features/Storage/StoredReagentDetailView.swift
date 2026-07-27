import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

struct StoredReagentDetailView: View {
    let storedReagentClientID: UUID
    let ontologyStore: ModelContainer

    @Environment(AppSession.self) private var appSession
    @Query private var storedReagents: [CachedStoredReagent]
    @Query private var actions: [CachedReagentAction]
    @Query private var annotations: [CachedStoredReagentAnnotation]
    @Query private var subscriptions: [CachedReagentSubscription]

    @State private var isShowingRecordActionSheet = false
    @State private var isShowingAddDocumentSheet = false
    @State private var documentSearchText = ""
    @State private var editingMetadataColumn: CachedMetadataColumn?
    @State private var isShowingAddMetadataColumnSheet = false

    private var storedReagent: CachedStoredReagent? {
        storedReagents.first(where: { $0.clientID == storedReagentClientID })
    }

    private var actionsHere: [CachedReagentAction] {
        actions
            .filter { $0.storedReagentClientID == storedReagentClientID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var documentsHere: [CachedStoredReagentAnnotation] {
        guard let serverID = storedReagent?.serverID else { return [] }
        return annotations
            .filter { $0.storedReagentServerID == serverID }
            .sorted { $0.folderName < $1.folderName }
    }

    private var searchedDocuments: [CachedStoredReagentAnnotation] {
        guard !documentSearchText.isEmpty else { return documentsHere }
        return documentsHere.filter {
            $0.annotationText.localizedCaseInsensitiveContains(documentSearchText) || $0.folderName.localizedCaseInsensitiveContains(documentSearchText)
        }
    }

    private var subscription: CachedReagentSubscription? {
        guard let serverID = storedReagent?.serverID else { return nil }
        return subscriptions.first(where: { $0.storedReagentServerID == serverID })
    }

    var body: some View {
        List {
            if let storedReagent {
                Section("Stock") {
                    let unit = storedReagent.reagentUnit ?? ""
                    LabeledContent("Quantity", value: "\(storedReagent.quantity.formatted()) \(unit)")
                    LabeledContent("Current Quantity", value: "\(storedReagent.currentQuantity.formatted()) \(unit)")
                    if let barcode = storedReagent.barcode {
                        LabeledContent("Barcode", value: barcode)
                    }
                    if let expirationDate = storedReagent.expirationDate {
                        LabeledContent("Expires", value: expirationDate)
                    }
                }
            }
            Section("History") {
                if actionsHere.isEmpty {
                    Text("No actions recorded yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(actionsHere) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(action.actionType == "add" ? "Add" : "Reserve") \(action.quantity.formatted()) \(storedReagent?.reagentUnit ?? "")")
                            if let notes = action.notes {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if storedReagent?.serverID != nil {
                MetadataFieldsSection(
                    metadataTableServerID: storedReagent?.metadataTableServerID,
                    ontologyStore: ontologyStore,
                    onColumnsChanged: { await refreshMetadataTable() },
                    editingColumn: $editingMetadataColumn,
                    isShowingAddColumnSheet: $isShowingAddMetadataColumnSheet
                )
                Section("Documents") {
                    if documentsHere.isEmpty {
                        Text("No documents yet")
                            .foregroundStyle(.secondary)
                    } else {
                        if documentsHere.count > 5 {
                            TextField("Search documents", text: $documentSearchText)
                                .accessibilityIdentifier("storedReagentDocumentSearchField")
                        }
                        if searchedDocuments.isEmpty {
                            Text("No documents match \"\(documentSearchText)\".")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(searchedDocuments) { annotation in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(annotation.annotationText)
                                    Text(annotation.folderName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onDelete(perform: deleteDocuments)
                        }
                    }
                    Button {
                        isShowingAddDocumentSheet = true
                    } label: {
                        Label("Add Document", systemImage: "doc.badge.plus")
                    }
                    .accessibilityIdentifier("addStoredReagentDocumentButton")
                }
                Section("Notifications") {
                    Toggle(
                        "Low Stock",
                        isOn: Binding(
                            get: { subscription?.notifyOnLowStock ?? false },
                            set: { updateSubscription(notifyOnLowStock: $0, notifyOnExpiry: subscription?.notifyOnExpiry ?? false) }
                        )
                    )
                    .accessibilityIdentifier("notifyOnLowStockToggle")
                    Toggle(
                        "Expiry",
                        isOn: Binding(
                            get: { subscription?.notifyOnExpiry ?? false },
                            set: { updateSubscription(notifyOnLowStock: subscription?.notifyOnLowStock ?? false, notifyOnExpiry: $0) }
                        )
                    )
                    .accessibilityIdentifier("notifyOnExpiryToggle")
                }
            }
        }
        .navigationTitle(storedReagent?.reagentName ?? "Reagent")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingRecordActionSheet = true
                } label: {
                    Label("Record Action", systemImage: "plus")
                }
                .accessibilityIdentifier("recordActionButton")
            }
        }
        .sheet(isPresented: $isShowingRecordActionSheet) {
            if let storedReagent {
                RecordReagentActionSheet(storedReagent: storedReagent)
            }
        }
        .sheet(isPresented: $isShowingAddDocumentSheet) {
            if let serverID = storedReagent?.serverID {
                AddStoredReagentAnnotationSheet(storedReagentServerID: serverID, reagentName: storedReagent?.reagentName ?? "Reagent")
            }
        }
        .sheet(item: $editingMetadataColumn) { column in
            MetadataValueEditSheet(column: column, projectServerID: nil, ontologyStore: ontologyStore)
        }
        .sheet(isPresented: $isShowingAddMetadataColumnSheet) {
            if let tableServerID = storedReagent?.metadataTableServerID {
                AddMetadataColumnSheet(tableServerID: tableServerID, ontologyStore: ontologyStore) {
                    await refreshMetadataTable()
                }
            }
        }
        .task(id: storedReagent?.serverID) {
            guard let serverID = storedReagent?.serverID, let userID = appSession.currentUserID else { return }
            let services = appSession.makeSyncServices()
            try? await services.storedReagentAnnotationSync.refetch(storedReagentServerID: serverID)
            try? await services.reagentSubscriptionSync.refetchMySubscription(storedReagentServerID: serverID, userID: userID)
            await refreshMetadataTable()
        }
    }

    private func refreshMetadataTable() async {
        guard let tableServerID = storedReagent?.metadataTableServerID else { return }
        _ = try? await appSession.makeSyncServices().inventorySync.refreshMetadataTable(metadataTableServerID: tableServerID)
    }

    private func deleteDocuments(at offsets: IndexSet) {
        let toDelete = offsets.map { searchedDocuments[$0] }
        Task {
            for annotation in toDelete {
                try? await appSession.makeSyncServices().storedReagentAnnotationSync.delete(serverID: annotation.serverID)
            }
        }
    }

    private func updateSubscription(notifyOnLowStock: Bool, notifyOnExpiry: Bool) {
        guard let serverID = storedReagent?.serverID, let userID = appSession.currentUserID else { return }
        Task {
            try? await appSession.makeSyncServices().reagentSubscriptionSync.subscribe(
                storedReagentServerID: serverID,
                userID: userID,
                notifyOnLowStock: notifyOnLowStock,
                notifyOnExpiry: notifyOnExpiry
            )
        }
    }
}
