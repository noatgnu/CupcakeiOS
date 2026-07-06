//
//  RootNavigationView.swift
//  Cupcake
//

import SwiftData
import SwiftUI

/// Switches between the login screen and the main tabs based on whether a `DeviceToken` is on
/// hand (or standalone mode is active). Exactly 4 top-level tabs, deliberately — iOS's `TabView`
/// collapses anything past 4 into a "More" overflow list, and any tab landing there that does its
/// own internal push navigation (a list pushing its detail view) shows a genuine double
/// back-button bug ("< More" and "< Jobs" simultaneously, from two nested navigation
/// controllers) — confirmed live, not theoretical. Storage+Instruments are merged into one
/// "Inventory" tab (`InventoryView`, a segmented switch between two independently-stacked
/// children, not one shared stack — avoids a `navigationDestination(for: Int64.self)` collision
/// between the two). Projects is reached via a push from within the Jobs tab (safe now that Jobs
/// itself is always directly visible, never in "More"). Settings is reached via a push from
/// within the Protocols tab, for the same reason — `ontologyStore` is threaded down to
/// `ProtocolListView` so it can attach it to just that pushed subtree.
struct RootNavigationView: View {
    @Environment(AppSession.self) private var appSession
    let ontologyStore: ModelContainer

    var body: some View {
        if appSession.canUseApp {
            TabView {
                ProtocolListView(ontologyStore: ontologyStore)
                    .tabItem { Label("Protocols", systemImage: "list.bullet.clipboard") }
                SessionListView()
                    .tabItem { Label("Sessions", systemImage: "clock") }
                JobListView()
                    .tabItem { Label("Jobs", systemImage: "list.clipboard") }
                InventoryView()
                    .tabItem { Label("Inventory", systemImage: "shippingbox") }
            }
        } else {
            NavigationStack {
                LoginView()
            }
        }
    }
}
