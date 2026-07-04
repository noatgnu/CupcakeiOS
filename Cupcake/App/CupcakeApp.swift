//
//  CupcakeApp.swift
//  Cupcake
//

import CupcakeModels
import SwiftData
import SwiftUI

@main
struct CupcakeApp: App {
    // CupcakeOntologyStore (Phase 4's read-only ontology reference data) is a separate
    // ModelContainer, added once CupcakeOntology has real @Model types to put in it.
    let cupcakeStore: ModelContainer
    @State private var appSession: AppSession

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state")
        if isUITesting {
            AppSession.resetPersistedStateForUITesting()
        }
        let store = Self.makeCupcakeStore(inMemoryOnly: isUITesting)
        cupcakeStore = store
        _appSession = State(initialValue: AppSession(modelContainer: store))
    }

    var body: some Scene {
        WindowGroup {
            RootNavigationView()
                .environment(appSession)
        }
        .modelContainer(cupcakeStore)
        #if os(macOS)
        .defaultSize(width: 1200, height: 700)
        #endif
    }

    private static func makeCupcakeStore(inMemoryOnly: Bool) -> ModelContainer {
        let schema = Schema([
            CachedProtocol.self,
            CachedProtocolSection.self,
            CachedProtocolStep.self,
            CachedSession.self,
            CachedStepAnnotation.self,
            CachedSessionAnnotation.self,
            CachedStorageObject.self,
            CachedReagent.self,
            CachedStepReagent.self,
            CachedStoredReagent.self,
            CachedInstrument.self,
            CachedInstrumentUsage.self,
            OutboxEntry.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemoryOnly)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create CupcakeStore ModelContainer: \(error)")
        }
    }
}
