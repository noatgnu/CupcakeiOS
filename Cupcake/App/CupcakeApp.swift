//
//  CupcakeApp.swift
//  Cupcake
//

import CupcakeModels
import CupcakeOntology
import SwiftData
import SwiftUI

@main
struct CupcakeApp: App {
    let cupcakeStore: ModelContainer
    // Independent lifecycle from `cupcakeStore` — read-only after import, safe to blow away/
    // rebuild per table, no sync/outbox involvement. Scoped to just the Settings tab's subtree
    // via its own `.modelContainer()` modifier below, not merged into the main store's schema.
    let cupcakeOntologyStore: ModelContainer
    @State private var appSession: AppSession

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state")
        if isUITesting {
            AppSession.resetPersistedStateForUITesting()
        }
        let store = Self.makeCupcakeStore(inMemoryOnly: isUITesting)
        cupcakeStore = store
        cupcakeOntologyStore = Self.makeOntologyStore(inMemoryOnly: isUITesting)
        _appSession = State(initialValue: AppSession(modelContainer: store))

        // `CachedStorageObject`/`CachedInstrument` are read-only server data (never
        // offline-createable) — in standalone mode there's genuinely no way to reach the
        // Storage/Instruments create flows without this, since neither the location nor the
        // instrument itself can ever be created locally. Seeds one fake "already synced" record
        // of each so the UI test suite can exercise `AddStoredReagentSheet`/`BookInstrumentSheet`
        // without a live backend.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-storage-instrument") {
            let context = ModelContext(store)
            let location = CachedStorageObject(serverID: 9001, objectType: "shelf", objectName: "Test Shelf")
            context.insert(location)
            let instrument = CachedInstrument(
                serverID: 9002,
                instrumentName: "Test Centrifuge",
                enabled: true,
                acceptsBookings: true,
                allowOverlappingBookings: false,
                maintenanceOverdue: false
            )
            context.insert(instrument)
            try? context.save()
        }
    }

    var body: some Scene {
        WindowGroup {
            // The ontology store is only attached to the Settings tab's subtree (inside
            // `RootNavigationView`, via its own nested `.modelContainer()`), not merged into the
            // main store's schema — `@Query` resolves against whichever container is nearest in
            // the view hierarchy, and `ModelContext.container` recovers the raw `ModelContainer`
            // wherever `OntologyImportService` needs to be constructed from it.
            RootNavigationView(ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
        }
        .modelContainer(cupcakeStore)
        #if os(macOS)
        .defaultSize(width: 1200, height: 700)
        #endif
    }

    private static func makeOntologyStore(inMemoryOnly: Bool) -> ModelContainer {
        do {
            return try CupcakeOntologyStore.makeContainer(inMemoryOnly: inMemoryOnly)
        } catch {
            fatalError("Could not create CupcakeOntologyStore ModelContainer: \(error)")
        }
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
            CachedReagentAction.self,
            CachedInstrument.self,
            CachedInstrumentUsage.self,
            CachedProject.self,
            CachedInstrumentJob.self,
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
