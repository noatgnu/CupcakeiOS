import CupcakeModels
import Foundation
import SwiftData
import SwiftUI

struct MainWindowRootView: View {
    let ontologyStore: ModelContainer

    @State private var appSession: AppSession
    @State private var modelContainer: ModelContainer
    @State private var namespaceID = UUID()
    @AppStorage("appAppearance") private var appearanceRawValue: String = AppAppearance.system.rawValue

    private static var hasCreatedInitialWindow = false

    init(ontologyStore: ModelContainer) {
        self.ontologyStore = ontologyStore

        let isFirstWindow = !Self.hasCreatedInitialWindow
        Self.hasCreatedInitialWindow = true

        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state")
        if isFirstWindow, isUITesting {
            AppSession.resetPersistedStateForUITesting()
            if !ProcessInfo.processInfo.arguments.contains("--ui-testing-enable-ontology-preload-prompt") {
                AppSession.suppressOntologyPreloadPromptForUITesting()
            }
        }

        let initialContext: AppSession.ActiveContext = (isFirstWindow && !isUITesting) ? AppSession.resolveInitialContext() : .none
        let store = CupcakeApp.makeCupcakeStore(storeFileName: AppSession.storeFileName(for: initialContext), inMemoryOnly: isUITesting)
        _modelContainer = State(initialValue: store)
        _appSession = State(initialValue: AppSession(modelContainer: store, activeContext: initialContext, isUITesting: isUITesting))

        if isFirstWindow {
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
    }

    private var resolvedColorScheme: ColorScheme? {
        (appSession.appearanceOverride ?? AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
    }

    var body: some View {
        RootNavigationView(ontologyStore: ontologyStore)
            .environment(appSession)
            .environment(\.namespaceID, namespaceID)
            .modelContainer(modelContainer)
            .preferredColorScheme(resolvedColorScheme)
            .id(ObjectIdentifier(modelContainer))
            .onOpenURL { url in
                appSession.handleDeepLink(url)
            }
            #if os(macOS)
            .background(MainWindowFocusTracker(namespaceID: namespaceID))
            #endif
            .onAppear {
                NamespaceRegistry.shared.register(appSession, for: namespaceID)
                #if os(macOS)
                NamespaceRegistry.shared.noteMainWindowFocused(namespaceID: namespaceID)
                #endif
                appSession.onRequestContainerSwap = { newContainer in
                    modelContainer = newContainer
                }
            }
            .task {
                if let pendingAction = NamespaceRegistry.shared.dequeuePendingLaunchAction() {
                    await perform(pendingAction)
                }
            }
            .onDisappear {
                NamespaceRegistry.shared.unregister(namespaceID)
            }
    }

    private func perform(_ action: PendingLaunchAction) async {
        switch action {
        case .knownInstance(let instance):
            appSession.switchToInstance(instance)
        case .signIn(let serverURLString, let username, let password):
            try? await appSession.signIn(serverURLString: serverURLString, username: username, password: password)
            await appSession.checkForLocalRecordsToImport()
            appSession.checkForOntologyPreloadPrompt()
        case .signInWithORCID(let serverURLString):
            try? await appSession.signInWithORCID(serverURLString: serverURLString)
            await appSession.checkForLocalRecordsToImport()
            appSession.checkForOntologyPreloadPrompt()
        case .continueOffline:
            appSession.continueOffline()
            appSession.checkForOntologyPreloadPrompt()
        }
    }
}
