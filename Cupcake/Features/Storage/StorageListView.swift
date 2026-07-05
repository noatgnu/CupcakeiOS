import CupcakeModels
import SwiftData
import SwiftUI

/// Storage locations are browsed by drilling down one level at a time with a back-button trail,
/// not an expandable tree — matches the reference web app's `storage-list.ts`, which fetches
/// only the current level's direct children (`stored_at: currentId`) and shows a breadcrumb, not
/// a client-side tree widget. `NavigationStack`'s own push/pop already gives the same drill-down
/// + "go back" behavior here, so there's no separate breadcrumb component to build.
///
/// Reagent row fields (name, quantity+unit, and `currentQuantity` only when it differs from
/// `quantity`) match `storage-list.html:236-329` exactly — the reference app has **no**
/// low-stock or expiring-soon indicator anywhere in this browse view (only in the create/edit
/// forms), so this doesn't invent one either.
struct StorageListView: View {
    var parentServerID: Int64?

    @Query private var allStorageObjects: [CachedStorageObject]
    @Query private var allStoredReagents: [CachedStoredReagent]
    @State private var isShowingAddReagentSheet = false

    private var childObjects: [CachedStorageObject] {
        allStorageObjects
            .filter { $0.storedAtServerID == parentServerID }
            .sorted { $0.objectName < $1.objectName }
    }

    private var reagentsHere: [CachedStoredReagent] {
        guard let parentServerID else { return [] }
        return allStoredReagents
            .filter { $0.storageObjectServerID == parentServerID }
            .sorted { ($0.reagentName ?? "") < ($1.reagentName ?? "") }
    }

    private var title: String {
        guard let parentServerID else { return "Storage" }
        return allStorageObjects.first(where: { $0.serverID == parentServerID })?.objectName ?? "Storage"
    }

    private func reagentSubtitle(_ reagent: CachedStoredReagent) -> String {
        let unit = reagent.reagentUnit ?? ""
        var text = "\(reagent.quantity.formatted()) \(unit)"
        if reagent.currentQuantity != reagent.quantity {
            text += " (Current: \(reagent.currentQuantity.formatted()) \(unit))"
        }
        return text
    }

    var body: some View {
        Group {
            if childObjects.isEmpty && reagentsHere.isEmpty {
                ContentUnavailableView(
                    "Empty",
                    systemImage: "shippingbox",
                    description: Text("No locations or reagents here.")
                )
            } else {
                List {
                    if !childObjects.isEmpty {
                        Section("Locations") {
                            ForEach(childObjects) { object in
                                NavigationLink(value: object.serverID) {
                                    Label(object.objectName, systemImage: "shippingbox")
                                }
                            }
                        }
                    }
                    if !reagentsHere.isEmpty {
                        Section("Reagents") {
                            ForEach(reagentsHere) { reagent in
                                NavigationLink(value: reagent.clientID) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reagent.reagentName ?? "Unnamed Reagent")
                                        Text(reagentSubtitle(reagent))
                                            .font(.caption)
                                            .foregroundStyle(reagent.currentQuantity != reagent.quantity ? .orange : .secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            if parentServerID != nil {
                ToolbarItem {
                    Button {
                        isShowingAddReagentSheet = true
                    } label: {
                        Label("Add Reagent", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addStoredReagentButton")
                }
            }
        }
        .sheet(isPresented: $isShowingAddReagentSheet) {
            if let parentServerID {
                AddStoredReagentSheet(storageObjectServerID: parentServerID, storageObjectName: title)
            }
        }
        .navigationDestination(for: Int64.self) { serverID in
            StorageListView(parentServerID: serverID)
        }
        .navigationDestination(for: UUID.self) { storedReagentClientID in
            StoredReagentDetailView(storedReagentClientID: storedReagentClientID)
        }
    }
}
