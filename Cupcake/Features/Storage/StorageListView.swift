import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Two-panel drill-down browser: storage locations on the left, reagents at the current location on the right.
struct StorageListView<SectionPicker: View>: View {
    @ViewBuilder let sectionPicker: () -> SectionPicker

    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Query private var allStorageObjects: [CachedStorageObject]
    @Query private var allStoredReagents: [CachedStoredReagent]

    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Storage")]
    @State private var isShowingAddReagentSheet = false
    @State private var isShowingNewLocationSheet = false
    @State private var editLocationTarget: CachedStorageObject?
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var locationSearchText = ""
    @State private var reagentSearchText = ""

    private var currentLocationID: Int64? {
        pathStack.last?.id
    }

    private var childObjects: [CachedStorageObject] {
        allStorageObjects
            .filter { $0.storedAtServerID == currentLocationID }
            .filter { locationSearchText.isEmpty || $0.objectName.localizedCaseInsensitiveContains(locationSearchText) }
            .sorted { $0.objectName < $1.objectName }
    }

    private var reagentsHere: [CachedStoredReagent] {
        guard let currentLocationID else { return [] }
        return allStoredReagents
            .filter { $0.storageObjectServerID == currentLocationID }
            .filter { reagentSearchText.isEmpty || $0.reagentName?.localizedCaseInsensitiveContains(reagentSearchText) == true }
            .sorted { ($0.reagentName ?? "") < ($1.reagentName ?? "") }
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
        TwoPanelExplorerView(pathStack: $pathStack) {
            ExplorerList(
                isEmpty: childObjects.isEmpty,
                emptyTitle: "No Sublocations",
                emptySystemImage: "shippingbox",
                emptyMessage: "This location has no sublocations."
            ) {
                ForEach(childObjects) { object in
                    Button {
                        enterLocation(object)
                    } label: {
                        Label(object.objectName, systemImage: "shippingbox")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("storageLocationRow_\(object.objectName)")
                    .contextMenu {
                        Button {
                            editLocationTarget = object
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await deleteLocation(object) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewLocationSheet = true
                    } label: {
                        Label("New Location", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newStorageLocationButton")
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if currentLocationID != nil {
                    TextField("Search reagents", text: $reagentSearchText)
                        .accessibilityIdentifier("reagentSearchField")
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                ExplorerList(
                    isEmpty: reagentsHere.isEmpty,
                    emptyTitle: "No Reagents",
                    emptySystemImage: "flask",
                    emptyMessage: "This location has no reagents."
                ) {
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
            .toolbar {
                if currentLocationID != nil {
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
            .navigationDestination(for: UUID.self) { storedReagentClientID in
                StoredReagentDetailView(storedReagentClientID: storedReagentClientID)
            }
        } sidebarHeader: {
            VStack(spacing: 8) {
                TextField("Search locations", text: $locationSearchText)
                    .accessibilityIdentifier("storageLocationSearchField")
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                sectionPicker()
            }
        }
        .sheet(isPresented: $isShowingAddReagentSheet) {
            if let currentLocationID {
                AddStoredReagentSheet(storageObjectServerID: currentLocationID, storageObjectName: pathStack.last?.name ?? "Storage")
            }
        }
        .sheet(isPresented: $isShowingNewLocationSheet) {
            EditStorageLocationSheet(parentServerID: currentLocationID)
        }
        .sheet(item: $editLocationTarget) { object in
            EditStorageLocationSheet(existingObject: object)
        }
        .alert("Couldn't delete location", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func enterLocation(_ object: CachedStorageObject) {
        pathStack.append(BreadcrumbSegment(id: object.serverID, name: object.objectName))
    }

    private func deleteLocation(_ object: CachedStorageObject) async {
        do {
            try await appSession.makeSyncServices().inventorySync.deleteStorageObject(serverID: object.serverID)
            modelContext.delete(object)
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
