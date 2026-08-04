import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct ProtocolListView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.namespaceID) private var namespaceID
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \CachedProtocol.createdAt, order: .reverse) private var protocols: [CachedProtocol]
    @Query private var outboxEntries: [OutboxEntry]

    @State private var selectedProtocolID: UUID?
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingNewProtocolSheet = false
    @State private var isShowingSyncIssues = false
    @State private var isShowingImportSheet = false
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "All Protocols")]
    @State private var listFilter: ProtocolListFilter?
    @State private var filteredServerIDs: Set<Int64> = []
    @State private var isLoadingFilter = false
    @State private var searchText = ""

    private func pendingSyncLabel(for protocolModel: CachedProtocol) -> String? {
        guard protocolModel.serverID == nil else { return nil }
        guard protocolModel.isLocallyAuthored else { return nil }
        return appSession.isAuthenticated ? "Pending sync" : "Local only"
    }

    private func accessRoleLabel(for protocolModel: CachedProtocol) -> String? {
        guard let currentUserID = appSession.currentUserID, let ownerServerID = protocolModel.ownerServerID, ownerServerID != currentUserID else { return nil }
        if protocolModel.editorServerIDs.contains(currentUserID) { return "Editor" }
        if protocolModel.viewerServerIDs.contains(currentUserID) { return "Viewer" }
        return "Group"
    }

    private var displayedProtocols: [CachedProtocol] {
        var result = protocols
        if listFilter != nil {
            result = result.filter { protocolModel in
                guard let serverID = protocolModel.serverID else { return false }
                return filteredServerIDs.contains(serverID)
            }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.protocolTitle.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            SelectableExplorerList(
                selection: $selectedProtocolID,
                isEmpty: displayedProtocols.isEmpty,
                emptyTitle: "No Protocols",
                emptySystemImage: "list.bullet.clipboard",
                emptyMessage: "Create a protocol to get started."
            ) {
                ForEach(displayedProtocols) { protocolModel in
                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Text(protocolModel.protocolTitle)
                            if let role = accessRoleLabel(for: protocolModel) {
                                Text(role)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.tertiary, in: Capsule())
                                    .accessibilityIdentifier("protocolAccessRoleBadge_\(protocolModel.protocolTitle)")
                            }
                        }
                        if let label = pendingSyncLabel(for: protocolModel) {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(protocolModel.clientID)
                }
            }
            .navigationTitle("Protocols")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewProtocolSheet = true
                    } label: {
                        Label("New Protocol", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("newProtocolButton")
                }
                if appSession.isAuthenticated {
                    ToolbarItem {
                        Menu {
                            Button("All Protocols") { Task { await applyFilter(nil) } }
                            Button("My Protocols") { Task { await applyFilter(.myProtocols) } }
                            Button("Shared With Me") { Task { await applyFilter(.sharedWithMe) } }
                            Button("Public") { Task { await applyFilter(.publicProtocols) } }
                            Button("Vaulted") { Task { await applyFilter(.vaultedProtocols) } }
                        } label: {
                            if isLoadingFilter {
                                ProgressView()
                            } else {
                                Label("Filter", systemImage: listFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .accessibilityIdentifier("protocolFilterMenu")
                    }
                    ToolbarItem {
                        Button {
                            isShowingImportSheet = true
                        } label: {
                            Label("Import from protocols.io…", systemImage: "square.and.arrow.down")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("importFromProtocolsIOButton")
                    }
                    ToolbarItem {
                        Button {
                            if PlatformWindowPreference.prefersSeparateWindow {
                                PlatformWindowPreference.openOrFocusWindow(id: "sync-issues", namespaceID: namespaceID, using: openWindow)
                            } else {
                                isShowingSyncIssues = true
                            }
                        } label: {
                            Label(outboxEntries.isEmpty ? "Sync Issues" : "Sync Issues (\(outboxEntries.count))", systemImage: outboxEntries.isEmpty ? "checkmark.icloud" : "exclamationmark.icloud")
                        }
                        .labelStyle(.iconOnly)
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
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .disabled(isSyncing)
                        .accessibilityIdentifier("syncNowButton")
                    }
                    #if os(macOS)
                    ToolbarItem {
                        Menu {
                            Button("Switch Instance…") {
                                appSession.leaveActiveInstance()
                            }
                            .accessibilityIdentifier("switchInstanceButton")
                            Button("Sign Out", role: .destructive) {
                                Task { await appSession.signOut() }
                            }
                            .accessibilityIdentifier("signOutButton")
                        } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier("accountMenu")
                    }
                    #endif
                } else if appSession.isStandalone {
                    ToolbarItem {
                        Button("Exit Offline Mode") {
                            appSession.exitStandalone()
                        }
                        .accessibilityIdentifier("exitOfflineModeButton")
                    }
                }
            }
            .sheet(isPresented: $isShowingNewProtocolSheet) {
                NewProtocolView()
            }
            .sheet(isPresented: $isShowingImportSheet) {
                ImportProtocolFromURLSheet()
            }
            .sheet(isPresented: $isShowingSyncIssues) {
                NavigationStack {
                    SyncIssuesView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingSyncIssues = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 360, minHeight: 400)
                #endif
            }
            .alert("Sync failed", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .newProtocolRequested)) { _ in
                isShowingNewProtocolSheet = true
            }
        } detail: {
            if let selectedProtocolID, let protocolModel = protocols.first(where: { $0.clientID == selectedProtocolID }) {
                ProtocolDetailView(protocolModel: protocolModel)
            } else {
                ExplorerList(
                    isEmpty: true,
                    emptyTitle: "No Protocol Selected",
                    emptySystemImage: "list.bullet.clipboard",
                    emptyMessage: "Select a protocol to see its details."
                ) { EmptyView() }
            }
        } sidebarHeader: {
            TextField("Search protocols", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("protocolSearchField")
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        .onChange(of: selectedProtocolID) { _, newValue in
            guard let newValue, let protocolModel = protocols.first(where: { $0.clientID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: protocolModel.serverID, name: protocolModel.protocolTitle)]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedProtocolID = nil
            }
            appSession.isShowingPushedDetail = newValue.count > 1 && horizontalSizeClass == .compact
        }
        .onAppear {
            appSession.isShowingPushedDetail = pathStack.count > 1 && horizontalSizeClass == .compact
        }
    }

    private func applyFilter(_ filter: ProtocolListFilter?) async {
        listFilter = filter
        guard let filter else {
            filteredServerIDs = []
            return
        }
        isLoadingFilter = true
        defer { isLoadingFilter = false }
        do {
            let ids = try await appSession.makeSyncServices().protocolSync.fetchProtocolIDs(filter: filter)
            filteredServerIDs = Set(ids)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func sync() async {
        guard appSession.isAuthenticated else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await appSession.syncAll()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
