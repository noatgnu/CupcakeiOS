//
//  RootNavigationView.swift
//  Cupcake
//

import SwiftUI

/// Single adaptive navigation shell: a 3-column `NavigationSplitView` on macOS/regular-width
/// iPad, degrading to a `NavigationStack` on compact-width iPhone. Real sidebar/detail content
/// (protocols, sessions, storage, instruments, settings) lands in Phase 1's Features/ work.
struct RootNavigationView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("Cupcake")
            }
            .navigationTitle("Cupcake")
        } detail: {
            Text("Select an item")
        }
    }
}

#Preview {
    RootNavigationView()
}
