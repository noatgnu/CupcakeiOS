//
//  RootNavigationView.swift
//  Cupcake
//

import SwiftUI

/// Switches between the login screen and the main tabs based on whether a `DeviceToken` is on
/// hand (or standalone mode is active). Protocols/Sessions match the reference web app's own nav
/// structure (`protocols-navbar.html`): separate top-level destinations, not nested inside one
/// another. Storage and Instruments are read-only lookup/browsing screens — sync infrastructure
/// for both existed well before any UI did, a gap independent of the Protocols/Sessions work.
struct RootNavigationView: View {
    @Environment(AppSession.self) private var appSession

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
            }
        } else {
            NavigationStack {
                LoginView()
            }
        }
    }
}
