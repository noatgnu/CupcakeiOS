import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

enum SessionListFilter {
    case mine
    case sharedWithMe
}

struct SessionListView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \CachedSession.createdAt, order: .reverse) private var sessions: [CachedSession]
    @Query private var allProtocols: [CachedProtocol]

    @State private var selectedSessionID: UUID?
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "All Sessions")]
    @State private var highlightedAnnotationServerID: Int64?
    @State private var isShowingNewSessionSheet = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var listFilter: SessionListFilter?

    private var displayedSessions: [CachedSession] {
        guard let listFilter, let currentUserID = appSession.currentUserID else { return sessions }
        switch listFilter {
        case .mine:
            return sessions.filter { $0.ownerServerID == currentUserID }
        case .sharedWithMe:
            return sessions.filter { session in
                session.ownerServerID != currentUserID
                    && (session.editorServerIDs.contains(currentUserID) || session.viewerServerIDs.contains(currentUserID))
            }
        }
    }

    private func protocolTitles(for session: CachedSession) -> [String] {
        session.protocolClientIDs.compactMap { clientID in
            allProtocols.first(where: { $0.clientID == clientID })?.protocolTitle
        }
    }

    private func accessRoleLabel(for session: CachedSession) -> String? {
        guard let currentUserID = appSession.currentUserID, let ownerServerID = session.ownerServerID, ownerServerID != currentUserID else { return nil }
        if session.editorServerIDs.contains(currentUserID) { return "Editor" }
        if session.viewerServerIDs.contains(currentUserID) { return "Viewer" }
        return "Group"
    }

    private func protocols(for session: CachedSession) -> [CachedProtocol] {
        session.protocolClientIDs.compactMap { clientID in
            allProtocols.first(where: { $0.clientID == clientID })
        }
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            SelectableExplorerList(
                selection: $selectedSessionID,
                isEmpty: displayedSessions.isEmpty,
                emptyTitle: "No Sessions Yet",
                emptySystemImage: "clock",
                emptyMessage: "Start a session from a protocol, or create one here."
            ) {
                ForEach(displayedSessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.name ?? "Untitled Session")
                            if let role = accessRoleLabel(for: session) {
                                Text(role)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.tertiary, in: Capsule())
                                    .accessibilityIdentifier("sessionAccessRoleBadge_\(session.name ?? "")")
                            }
                        }
                        HStack(spacing: 4) {
                            Text(session.status)
                            let titles = protocolTitles(for: session)
                            if !titles.isEmpty {
                                Text("· \(titles.joined(separator: ", "))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tag(session.clientID)
                    .accessibilityIdentifier("sessionRow")
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewSessionSheet = true
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("newStandaloneSessionButton")
                }
                if appSession.isAuthenticated {
                    ToolbarItem {
                        Menu {
                            Button("All Sessions") { listFilter = nil }
                            Button("My Sessions") { listFilter = .mine }
                            Button("Shared With Me") { listFilter = .sharedWithMe }
                        } label: {
                            Label("Filter", systemImage: listFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("sessionFilterMenu")
                    }
                }
            }
        } detail: {
            if let selectedSessionID, let session = sessions.first(where: { $0.clientID == selectedSessionID }) {
                SessionDetailView(sessionClientID: selectedSessionID, protocols: protocols(for: session), highlightAnnotationServerID: highlightedAnnotationServerID)
                    .id(selectedSessionID)
            } else {
                ExplorerList(
                    isEmpty: true,
                    emptyTitle: "No Session Selected",
                    emptySystemImage: "clock",
                    emptyMessage: "Select a session to see its details."
                ) { EmptyView() }
            }
        }
        .sheet(isPresented: $isShowingNewSessionSheet) {
            NewSessionSheet { name, enabled, protocolClientIDs in
                Task { await createSession(name: name, enabled: enabled, protocolClientIDs: protocolClientIDs) }
            }
        }
        .alert("Couldn't create session", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
            isShowingNewSessionSheet = true
        }
        .onChange(of: selectedSessionID) { _, newValue in
            guard let newValue, let session = sessions.first(where: { $0.clientID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: nil, name: session.name ?? "Untitled Session")]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedSessionID = nil
            }
            appSession.isShowingPushedDetail = newValue.count > 1 && horizontalSizeClass == .compact
        }
        .onAppear {
            appSession.isShowingPushedDetail = pathStack.count > 1 && horizontalSizeClass == .compact
        }
        .onChange(of: appSession.pendingDeepLink) { _, newValue in
            applyDeepLink(newValue)
        }
        .onAppear {
            applyDeepLink(appSession.pendingDeepLink)
        }
    }

    private func applyDeepLink(_ target: DeepLinkTarget?) {
        guard let target, sessions.contains(where: { $0.clientID == target.sessionClientID }) else { return }
        _ = appSession.consumeDeepLink()
        selectedSessionID = target.sessionClientID
        highlightedAnnotationServerID = target.annotationServerID
    }

    private func createSession(name: String, enabled: Bool, protocolClientIDs: [UUID]) async {
        let (clientID, outcome) = await SessionCreation.createSession(
            name: name,
            enabled: enabled,
            protocolClientIDs: protocolClientIDs,
            canAuthorOnline: appSession.isAuthenticated,
            modelContext: modelContext,
            appSession: appSession
        )
        selectedSessionID = clientID
        if case .failed(let message) = outcome {
            errorMessage = "Saved locally, but couldn't sync: \(message)"
            isShowingError = true
        }
    }
}
