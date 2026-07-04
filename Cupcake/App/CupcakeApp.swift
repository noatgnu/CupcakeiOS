//
//  CupcakeApp.swift
//  Cupcake
//

import SwiftUI

@main
struct CupcakeApp: App {
    // Phase 1c wires up the two real ModelContainers here (CupcakeStore, CupcakeOntologyStore)
    // once CupcakeModels has its first @Model types.
    var body: some Scene {
        WindowGroup {
            RootNavigationView()
        }
    }
}
