import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

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

    private func protocolTitles(for session: CachedSession) -> [String] {
        session.protocolClientIDs.compactMap { clientID in
            allProtocols.first(where: { $0.clientID == clientID })?.protocolTitle
        }
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
                isEmpty: sessions.isEmpty,
                emptyTitle: "No Sessions Yet",
                emptySystemImage: "clock",
                emptyMessage: "Start a session from a protocol, or create one here."
            ) {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name ?? "Untitled Session")
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
                    .accessibilityIdentifier("newSessionButton")
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
