
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
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(UITestingSceneCleaner.self) private var sceneCleaner
    #endif

    let cupcakeOntologyStore: ModelContainer
    @AppStorage("appAppearance") private var appearanceRawValue: String = AppAppearance.system.rawValue

    private func resolvedColorScheme(for session: AppSession) -> ColorScheme? {
        (session.appearanceOverride ?? AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
    }

    init() {
        #if os(macOS)
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
        #endif
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state")
        cupcakeOntologyStore = Self.makeOntologyStore(inMemoryOnly: isUITesting)
    }

    @ViewBuilder
    private func auxiliaryContent(for windowID: AuxiliaryWindowID?, windowKey: String, @ViewBuilder content: (AppSession) -> some View) -> some View {
        if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
            content(session)
                .environment(session)
                .environment(\.namespaceID, windowID.namespaceID)
                .modelContainer(session.modelContainer)
                .preferredColorScheme(resolvedColorScheme(for: session))
                #if os(macOS)
                .background(WindowRegistrar(key: "\(windowKey)|\(windowID.namespaceID.uuidString)"))
                #endif
        } else {
            OrphanedAuxiliaryWindowView()
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowRootView(ontologyStore: cupcakeOntologyStore)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 700)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Protocol…") { NotificationCenter.default.post(name: .newProtocolRequested, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("New Job…") { NotificationCenter.default.post(name: .newJobRequested, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Session…") { NotificationCenter.default.post(name: .newSessionRequested, object: nil) }
                Button("New Project…") { NotificationCenter.default.post(name: .newProjectRequested, object: nil) }
                Button("New Window") { openWindow(id: "main") }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(after: .windowArrangement) {
                Button("Metadata Table Templates") { openFocusedAuxiliaryWindow(id: "table-template-manager") }
                Button("Column Templates") { openFocusedAuxiliaryWindow(id: "column-template-manager") }
                Button("Metadata Tables") { openFocusedAuxiliaryWindow(id: "metadata-tables-browser") }
                Button("Lab Groups") { openFocusedAuxiliaryWindow(id: "lab-group-manager") }
                Button("My Favourites") { openFocusedAuxiliaryWindow(id: "favourites-manager") }
                Button("Sync Issues") { openFocusedAuxiliaryWindow(id: "sync-issues") }
                Button("Async Tasks") { openFocusedAuxiliaryWindow(id: "async-task-center") }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openFocusedAuxiliaryWindow(id: "settings") }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif

        WindowGroup("Metadata Table Templates", id: "table-template-manager", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "table-template-manager") { _ in
                NavigationStack {
                    TableTemplateManagementView(ontologyStore: cupcakeOntologyStore)
                }
            }
        }
        .defaultSize(width: 900, height: 780)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Column Templates", id: "column-template-manager", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "column-template-manager") { _ in
                NavigationStack {
                    ColumnTemplateManagementSheet()
                }
            }
        }
        .defaultSize(width: 480, height: 560)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Metadata Tables", id: "metadata-tables-browser", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "metadata-tables-browser") { _ in
                NavigationStack {
                    MetadataTablesBrowserView(ontologyStore: cupcakeOntologyStore)
                }
            }
        }
        .defaultSize(width: 700, height: 600)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Lab Groups", id: "lab-group-manager", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "lab-group-manager") { _ in
                NavigationStack {
                    LabGroupListView()
                }
            }
        }
        .defaultSize(width: 700, height: 560)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("My Favourites", id: "favourites-manager", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "favourites-manager") { _ in
                NavigationStack {
                    FavouritesManagementSheet()
                }
            }
        }
        .defaultSize(width: 460, height: 520)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Sync Issues", id: "sync-issues", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "sync-issues") { _ in
                NavigationStack {
                    SyncIssuesView()
                }
            }
        }
        .defaultSize(width: 420, height: 460)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Async Tasks", id: "async-task-center", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "async-task-center") { _ in
                NavigationStack {
                    AsyncTaskCenterView()
                }
            }
        }
        .defaultSize(width: 420, height: 480)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Edit Value", id: "metadata-value-editor", for: MetadataValueEditWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                MetadataValueEditWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 360, height: 480)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Metadata Table", id: "metadata-table-detail", for: MetadataTableDetailWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                MetadataTableDetailWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 700, height: 800)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Protocol", id: "protocol-detail-window", for: ProtocolDetailWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                ProtocolDetailWindowContent(windowID: windowID)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 600, height: 700)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Job", id: "job-detail-window", for: JobDetailWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                JobDetailWindowContent(windowID: windowID, ontologyStore: cupcakeOntologyStore)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 500, height: 600)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Session", id: "session-detail-window", for: SessionDetailWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                SessionDetailWindowContent(windowID: windowID)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 600, height: 700)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Step", id: "step-session-window", for: StepSessionWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                StepSessionWindowContent(windowID: windowID)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 420, height: 500)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Step", id: "step-detail-window", for: StepDetailWindowID.self) { $windowID in
            if let windowID, let session = NamespaceRegistry.shared.session(for: windowID.namespaceID) {
                StepDetailWindowContent(windowID: windowID)
                    .environment(session)
                    .environment(\.namespaceID, windowID.namespaceID)
                    .modelContainer(session.modelContainer)
                    .preferredColorScheme(resolvedColorScheme(for: session))
            } else {
                OrphanedAuxiliaryWindowView()
            }
        }
        .defaultSize(width: 420, height: 500)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif

        WindowGroup("Settings", id: "settings", for: AuxiliaryWindowID.self) { $windowID in
            auxiliaryContent(for: windowID, windowKey: "settings") { _ in
                SettingsView()
                    .modelContainer(cupcakeOntologyStore)
                    #if os(macOS)
                    .frame(minWidth: 560, minHeight: 620)
                    #endif
            }
        }
        .defaultSize(width: 560, height: 620)
        #if os(macOS)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }

    #if os(macOS)
    private func openFocusedAuxiliaryWindow(id: String) {
        guard let namespaceID = NamespaceRegistry.shared.focusedOrFirstNamespaceID else { return }
        PlatformWindowPreference.openOrFocusWindow(id: id, namespaceID: namespaceID, using: openWindow)
    }
    #endif

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

private struct OrphanedAuxiliaryWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ContentUnavailableView("Window Unavailable", systemImage: "questionmark.square.dashed")
            .task {
                dismissWindow()
            }
    }
}
