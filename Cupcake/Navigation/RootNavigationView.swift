//
//  RootNavigationView.swift
//  Cupcake
//

import SwiftData
import SwiftUI

/// Switches between the login screen and the main tabs based on whether a `DeviceToken` is on
/// hand (or standalone mode is active). Protocols/Sessions match the reference web app's own nav
/// structure (`protocols-navbar.html`): separate top-level destinations, not nested inside one
/// another. Storage and Instruments are read-only lookup/browsing screens — sync infrastructure
/// for both existed well before any UI did, a gap independent of the Protocols/Sessions work.
/// Settings gets its own `.modelContainer()` for `ontologyStore` — a separate, independent-
/// lifecycle container from the main `cupcakeStore` the rest of the app uses, scoped to just
/// this tab's subtree rather than merged into the app-wide schema.
struct RootNavigationView: View {
    @Environment(AppSession.self) private var appSession
    let ontologyStore: ModelContainer

    var body: some View {
        if appSession.canUseApp {
            TabView {
                ProtocolListView()
                    .tabItem { Label("Protocols", systemImage: "list.bullet.clipboard") }
                SessionListView()
                    .tabItem { Label("Sessions", systemImage: "clock") }
                NavigationStack {
                    StorageListView(parentServerID: nil)
                }
                .tabItem { Label("Storage", systemImage: "shippingbox") }
                InstrumentListView()
                    .tabItem { Label("Instruments", systemImage: "wrench.and.screwdriver") }
                JobListView()
                    .tabItem { Label("Jobs", systemImage: "list.clipboard") }
                NavigationStack {
                    SettingsView()
                }
                .modelContainer(ontologyStore)
                .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        } else {
            NavigationStack {
                LoginView()
            }
        }
    }
}
