//
//  RootNavigationView.swift
//  Cupcake
//

import SwiftUI

/// Switches between the login screen and the main Protocols/Sessions tabs based on whether a
/// `DeviceToken` is on hand (or standalone mode is active). Matches the reference web app's own
/// nav structure (`protocols-navbar.html`): Protocols and Sessions are separate top-level
/// destinations — session browsing is not nested inside protocol editing, since a session isn't
/// scoped to "the protocol you happened to start it from" (multiple independent sessions can
/// exist per protocol, and the only way back to one you've navigated away from is this list).
struct RootNavigationView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        if appSession.canUseApp {
            TabView {
                ProtocolListView()
                    .tabItem { Label("Protocols", systemImage: "list.bullet.clipboard") }
                SessionListView()
                    .tabItem { Label("Sessions", systemImage: "clock") }
            }
        } else {
            NavigationStack {
                LoginView()
            }
        }
    }
}
