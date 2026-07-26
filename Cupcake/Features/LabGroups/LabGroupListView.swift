import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct LabGroupListView: View {
    @Environment(AppSession.self) private var appSession
    @Query(sort: \CachedLabGroup.createdAt, order: .reverse) private var labGroups: [CachedLabGroup]

    @State private var isShowingNewGroupSheet = false
    @State private var isShowingPendingInvitations = false
    @State private var selectedGroupServerID: Int64?
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "All Lab Groups")]

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            SelectableExplorerList(
                selection: $selectedGroupServerID,
                isEmpty: labGroups.isEmpty,
                emptyTitle: "No Lab Groups",
                emptySystemImage: "person.3",
                emptyMessage: "Create a lab group or accept a pending invitation to get started."
            ) {
                ForEach(labGroups, id: \.serverID) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.fullPathNames.isEmpty ? group.name : group.fullPathNames.joined(separator: " › "))
                        HStack(spacing: 6) {
                            Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                            if group.isCreator {
                                Text("• Creator")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tag(group.serverID)
                    .accessibilityIdentifier("labGroupRow_\(group.name)")
                }
            }
            .navigationTitle("Lab Groups")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingPendingInvitations = true
                    } label: {
                        Label("Invitations", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("pendingInvitationsButton")
                }
                ToolbarItem {
                    Button {
                        isShowingNewGroupSheet = true
                    } label: {
                        Label("New Lab Group", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newLabGroupButton")
                }
            }
            .sheet(isPresented: $isShowingNewGroupSheet) {
                NewLabGroupSheet()
            }
            .sheet(isPresented: $isShowingPendingInvitations) {
                NavigationStack {
                    PendingInvitationsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingPendingInvitations = false }
                            }
                        }
                }
                .frame(minWidth: 360, minHeight: 420)
            }
        } detail: {
            if let selectedGroupServerID, let group = labGroups.first(where: { $0.serverID == selectedGroupServerID }) {
                LabGroupDetailView(labGroupServerID: group.serverID)
                    .id(group.serverID)
            } else {
                ExplorerList(
                    isEmpty: true,
                    emptyTitle: "No Lab Group Selected",
                    emptySystemImage: "person.3",
                    emptyMessage: "Select a lab group to see its members and settings."
                ) { EmptyView() }
            }
        }
        .onChange(of: selectedGroupServerID) { _, newValue in
            guard let newValue, let group = labGroups.first(where: { $0.serverID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: nil, name: group.name)]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedGroupServerID = nil
            }
        }
        .task {
            try? await appSession.makeSyncServices().labGroupSync.refetchAll()
        }
    }
}
