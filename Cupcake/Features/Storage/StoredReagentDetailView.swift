import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

/// Shows a stored reagent's stock, action history, documents, and notification preferences.
struct StoredReagentDetailView: View {
    let storedReagentClientID: UUID

    @Environment(AppSession.self) private var appSession
    @Query private var storedReagents: [CachedStoredReagent]
    @Query private var actions: [CachedReagentAction]
    @Query private var annotations: [CachedStoredReagentAnnotation]
    @Query private var subscriptions: [CachedReagentSubscription]

    @State private var isShowingRecordActionSheet = false
    @State private var isShowingAddDocumentSheet = false

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
                Section("Documents") {
                    if documentsHere.isEmpty {
                        Text("No documents yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(documentsHere) { annotation in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(annotation.annotationText)
                                Text(annotation.folderName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: deleteDocuments)
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
        .task(id: storedReagent?.serverID) {
            guard let serverID = storedReagent?.serverID, let userID = appSession.currentUserID else { return }
            let services = appSession.makeSyncServices()
            try? await services.storedReagentAnnotationSync.refetch(storedReagentServerID: serverID)
            try? await services.reagentSubscriptionSync.refetchMySubscription(storedReagentServerID: serverID, userID: userID)
        }
    }

    private func deleteDocuments(at offsets: IndexSet) {
        let toDelete = offsets.map { documentsHere[$0] }
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
