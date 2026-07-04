import CupcakeModels
import SwiftData
import SwiftUI

/// A flat, all-protocols list of every session — matches the reference web app's separate
/// "My Sessions" nav tab (`protocols-navbar.html`), which lists sessions globally rather than
/// per-protocol. Every "Start Session" always creates a brand-new, independent session (no
/// "resume" concept there or here), so this is the only way back to a session once you've
/// navigated away from it.
struct SessionListView: View {
    @Query(sort: \CachedSession.createdAt, order: .reverse) private var sessions: [CachedSession]
    @Query private var allProtocols: [CachedProtocol]

    private func protocolTitle(for session: CachedSession) -> String? {
        guard let protocolClientID = session.primaryProtocolClientID else { return nil }
        return allProtocols.first(where: { $0.clientID == protocolClientID })?.protocolTitle
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock",
                        description: Text("Start a session from a protocol to see it here.")
                    )
                } else {
                    List(sessions) { session in
                        NavigationLink(value: session.clientID) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name ?? "Untitled Session")
                                HStack(spacing: 4) {
                                    Text(session.status)
                                    if let title = protocolTitle(for: session) {
                                        Text("· \(title)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("sessionRow")
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: UUID.self) { sessionClientID in
                if let session = sessions.first(where: { $0.clientID == sessionClientID }),
                   let protocolClientID = session.primaryProtocolClientID,
                   let protocolModel = allProtocols.first(where: { $0.clientID == protocolClientID }) {
                    SessionDetailView(sessionClientID: sessionClientID, protocolModel: protocolModel)
                } else {
                    Text("This session's protocol is no longer available.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
