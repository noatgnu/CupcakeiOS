
import CupcakeModels
import CupcakeOntology
import Foundation
import SwiftData
import SwiftUI

@main
struct CupcakeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacWindowPlacementFixer.self) private var windowPlacementFixer
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var cupcakeStore: ModelContainer
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
        let initialContext: AppSession.ActiveContext = isUITesting ? .none : AppSession.resolveInitialContext()
        let store = Self.makeCupcakeStore(storeFileName: AppSession.storeFileName(for: initialContext), inMemoryOnly: isUITesting)
        _cupcakeStore = State(initialValue: store)
        cupcakeOntologyStore = Self.makeOntologyStore(inMemoryOnly: isUITesting)
        _appSession = State(initialValue: AppSession(modelContainer: store, activeContext: initialContext, isUITesting: isUITesting))

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

        if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-real-protocol") {
            RealProtocolFixture.seed(into: ModelContext(store))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootNavigationView(ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
                .id(ObjectIdentifier(cupcakeStore))
                .onOpenURL { url in
                    appSession.handleDeepLink(url)
                }
                .onAppear {
                    appSession.onRequestContainerSwap = { newContainer in
                        cupcakeStore = newContainer
                    }
                }
        }
        .modelContainer(cupcakeStore)
        #if os(macOS)
        .defaultSize(width: 1200, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Protocol…") { NotificationCenter.default.post(name: .newProtocolRequested, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("New Job…") { NotificationCenter.default.post(name: .newJobRequested, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Session…") { NotificationCenter.default.post(name: .newSessionRequested, object: nil) }
                Button("New Project…") { NotificationCenter.default.post(name: .newProjectRequested, object: nil) }
            }
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(after: .windowArrangement) {
                Button("Metadata Table Templates") { PlatformWindowPreference.openOrFocusWindow(id: "table-template-manager", using: openWindow) }
                Button("Column Templates") { PlatformWindowPreference.openOrFocusWindow(id: "column-template-manager", using: openWindow) }
                Button("Metadata Tables") { PlatformWindowPreference.openOrFocusWindow(id: "metadata-tables-browser", using: openWindow) }
                Button("Lab Groups") { PlatformWindowPreference.openOrFocusWindow(id: "lab-group-manager", using: openWindow) }
                Button("My Favourites") { PlatformWindowPreference.openOrFocusWindow(id: "favourites-manager", using: openWindow) }
                Button("Sync Issues") { PlatformWindowPreference.openOrFocusWindow(id: "sync-issues", using: openWindow) }
                Button("Async Tasks") { PlatformWindowPreference.openOrFocusWindow(id: "async-task-center", using: openWindow) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { PlatformWindowPreference.openOrFocusWindow(id: "settings", using: openWindow) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif

        WindowGroup("Metadata Table Templates", id: "table-template-manager") {
            NavigationStack {
                TableTemplateManagementView(ontologyStore: cupcakeOntologyStore)
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 480, height: 520)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Column Templates", id: "column-template-manager") {
            NavigationStack {
                ColumnTemplateManagementSheet()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 380, height: 420)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Metadata Tables", id: "metadata-tables-browser") {
            NavigationStack {
                MetadataTablesBrowserView(ontologyStore: cupcakeOntologyStore)
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 700, height: 600)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Lab Groups", id: "lab-group-manager") {
            NavigationStack {
                LabGroupListView()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 700, height: 560)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("My Favourites", id: "favourites-manager") {
            NavigationStack {
                FavouritesManagementSheet()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 380, height: 440)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Sync Issues", id: "sync-issues") {
            NavigationStack {
                SyncIssuesView()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 360, height: 400)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Async Tasks", id: "async-task-center") {
            NavigationStack {
                AsyncTaskCenterView()
            }
            .environment(appSession)
            .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 420, height: 480)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Edit Value", id: "metadata-value-editor", for: MetadataValueEditWindowID.self) { $windowID in
            MetadataValueEditWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 360, height: 480)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Metadata Table", id: "metadata-table-detail", for: MetadataTableDetailWindowID.self) { $windowID in
            MetadataTableDetailWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 700, height: 600)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Protocol", id: "protocol-detail-window", for: ProtocolDetailWindowID.self) { $windowID in
            ProtocolDetailWindowContent(windowID: windowID)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 600, height: 700)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Job", id: "job-detail-window", for: JobDetailWindowID.self) { $windowID in
            JobDetailWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 500, height: 600)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Session", id: "session-detail-window", for: SessionDetailWindowID.self) { $windowID in
            SessionDetailWindowContent(windowID: windowID)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 600, height: 700)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Step", id: "step-session-window", for: StepSessionWindowID.self) { $windowID in
            StepSessionWindowContent(windowID: windowID)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 420, height: 500)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Step", id: "step-detail-window", for: StepDetailWindowID.self) { $windowID in
            StepDetailWindowContent(windowID: windowID)
                .environment(appSession)
                .preferredColorScheme(resolvedColorScheme)
        }
        .modelContainer(cupcakeStore)
        .defaultSize(width: 420, height: 500)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environment(appSession)
                .modelContainer(cupcakeOntologyStore)
                .preferredColorScheme(resolvedColorScheme)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        }
        .defaultSize(width: 500, height: 400)
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }

    private static func makeOntologyStore(inMemoryOnly: Bool) -> ModelContainer {
        do {
            return try CupcakeOntologyStore.makeContainer(inMemoryOnly: inMemoryOnly)
        } catch {
            fatalError("Could not create CupcakeOntologyStore ModelContainer: \(error)")
        }
    }

    static func makeCupcakeStore(storeFileName: String = "CupcakeStore.store", inMemoryOnly: Bool) -> ModelContainer {
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
            InstanceMetadata.self,
        ])
        let configuration: ModelConfiguration
        if inMemoryOnly {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let storeURL = Self.applicationSupportDirectory.appendingPathComponent(storeFileName)
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create CupcakeStore ModelContainer: \(error)")
        }
    }

    static var applicationSupportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
