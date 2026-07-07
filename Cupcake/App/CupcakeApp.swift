//
//  CupcakeApp.swift
//  Cupcake
//

import CupcakeModels
import CupcakeOntology
import Foundation
import SwiftData
import SwiftUI

@main
struct CupcakeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacWindowPlacementFixer.self) private var windowPlacementFixer
    #endif

    let cupcakeStore: ModelContainer
    let cupcakeOntologyStore: ModelContainer
    @State private var appSession: AppSession
    @AppStorage("appAppearance") private var appearanceRawValue: String = AppAppearance.system.rawValue

    private var resolvedColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
    }

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state")
        if isUITesting {
            AppSession.resetPersistedStateForUITesting()
        }
        let store = Self.makeCupcakeStore(inMemoryOnly: isUITesting)
        cupcakeStore = store
        cupcakeOntologyStore = Self.makeOntologyStore(inMemoryOnly: isUITesting)
        _appSession = State(initialValue: AppSession(modelContainer: store))

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
            RootNavigationView(ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
                .onOpenURL { url in
                    appSession.handleDeepLink(url)
                }
        }
        .modelContainer(cupcakeStore)
        #if os(macOS)
        .defaultSize(width: 1200, height: 700)
        #endif

        WindowGroup("Metadata Table Templates", id: "table-template-manager") {
            NavigationStack {
                TableTemplateManagementView()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 480, height: 520)

        WindowGroup("Column Templates", id: "column-template-manager") {
            NavigationStack {
                ColumnTemplateManagementSheet()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 380, height: 420)

        WindowGroup("My Favourites", id: "favourites-manager") {
            NavigationStack {
                FavouritesManagementSheet()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 380, height: 440)

        WindowGroup("Sync Issues", id: "sync-issues") {
            NavigationStack {
                SyncIssuesView()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 360, height: 400)

        WindowGroup("Edit Value", id: "metadata-value-editor", for: MetadataValueEditWindowID.self) { $windowID in
            MetadataValueEditWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 360, height: 480)

        WindowGroup("Protocol", id: "protocol-detail-window", for: ProtocolDetailWindowID.self) { $windowID in
            ProtocolDetailWindowContent(windowID: windowID)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 600, height: 700)

        WindowGroup("Job", id: "job-detail-window", for: JobDetailWindowID.self) { $windowID in
            JobDetailWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 500, height: 600)

        WindowGroup("Session", id: "session-detail-window", for: SessionDetailWindowID.self) { $windowID in
            SessionDetailWindowContent(windowID: windowID)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 600, height: 700)

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(cupcakeOntologyStore)
                .preferredColorScheme(resolvedColorScheme)
                .frame(minWidth: 500, minHeight: 400)
        }
        #else
        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .modelContainer(cupcakeOntologyStore)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 500, height: 400)
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
            CachedAnnotationFolder.self,
            CachedFolderAnnotation.self,
            CachedStorageObject.self,
            CachedReagent.self,
            CachedStepReagent.self,
            CachedStoredReagent.self,
            CachedReagentAction.self,
            CachedInstrument.self,
            CachedInstrumentUsage.self,
            CachedProject.self,
            CachedInstrumentJob.self,
            CachedLabGroup.self,
            CachedMetadataTable.self,
            CachedMetadataColumn.self,
            CachedMetadataTableTemplate.self,
            CachedInstrumentJobAnnotation.self,
            CachedTimeKeeper.self,
            CachedMaintenanceLog.self,
            CachedStepVariation.self,
            CachedProtocolRating.self,
            CachedStoredReagentAnnotation.self,
            CachedReagentSubscription.self,
            CachedSamplePool.self,
            OutboxEntry.self,
        ])
        let configuration: ModelConfiguration
        if inMemoryOnly {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let storeURL = Self.applicationSupportDirectory.appendingPathComponent("CupcakeStore.store")
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create CupcakeStore ModelContainer: \(error)")
        }
    }

    private static var applicationSupportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
