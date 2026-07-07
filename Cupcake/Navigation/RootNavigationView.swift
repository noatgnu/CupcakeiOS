//
//  RootNavigationView.swift
//  Cupcake
//

import SwiftData
import SwiftUI

/// Switches between the login screen and the main 4-section layout, via a floating icon selector.
struct RootNavigationView: View {
    @Environment(AppSession.self) private var appSession
    let ontologyStore: ModelContainer

    private enum Tab: CaseIterable {
        case protocols, sessions, jobs, inventory

        var label: String {
            switch self {
            case .protocols: "Protocols"
            case .sessions: "Sessions"
            case .jobs: "Jobs"
            case .inventory: "Inventory"
            }
        }

        var systemImage: String {
            switch self {
            case .protocols: "list.bullet.clipboard"
            case .sessions: "clock"
            case .jobs: "list.clipboard"
            case .inventory: "shippingbox"
            }
        }
    }

    @State private var selectedTab: Tab = .protocols

    var body: some View {
        Group {
            if appSession.canUseApp {
                ZStack {
                    switch selectedTab {
                    case .protocols:
                        ProtocolListView(ontologyStore: ontologyStore)
                    case .sessions:
                        SessionListView()
                    case .jobs:
                        JobListView(ontologyStore: ontologyStore)
                    case .inventory:
                        InventoryView()
                    }
                }
                .overlay(alignment: .bottom) {
                    floatingTabSelector
                        .padding(.bottom, 16)
                }
                .task {
                    try? await appSession.syncAll()
                }
            } else {
                NavigationStack {
                    LoginView()
                }
            }
        }
        .alert(
            "Import Local Notebook?",
            isPresented: Binding(
                get: { appSession.pendingLocalImportCount != nil },
                set: { if !$0 { appSession.dismissLocalImportPrompt() } }
            )
        ) {
            Button("Not Now", role: .cancel) { appSession.dismissLocalImportPrompt() }
            Button("Import") {
                Task { await appSession.importLocalNotebook() }
            }
            .accessibilityIdentifier("importLocalNotebookButton")
        } message: {
            Text("You have \(appSession.pendingLocalImportCount ?? 0) item(s) created while offline. Import them to this server now?")
        }
        .onChange(of: appSession.pendingDeepLink) { _, newValue in
            if newValue != nil {
                selectedTab = .sessions
            }
        }
    }

    private var floatingTabSelector: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                        .background(
                            Circle().fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tab.label)
                .accessibilityLabel(tab.label)
                .accessibilityIdentifier(tab.label)
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
