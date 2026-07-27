import AuthenticationServices
import CupcakeAuth
import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import Foundation
import Network
import SwiftData
import SwiftUI

struct DeepLinkTarget: Equatable {
    let sessionClientID: UUID
    let annotationServerID: Int64?
}

struct SyncServices {
    let protocolSync: ProtocolSyncService
    let sessionSync: SessionSyncService
    let stepAnnotationSync: StepAnnotationSyncService
    let sessionAnnotationSync: SessionAnnotationSyncService
    let inventorySync: InventorySyncService
    let instrumentSync: InstrumentSyncService
    let stepReagentSync: StepReagentSyncService
    let projectSync: ProjectSyncService
    let instrumentJobSync: InstrumentJobSyncService
    let labGroupSync: LabGroupSyncService
    let metadataTableTemplateSync: MetadataTableTemplateSyncService
    let instrumentJobAnnotationSync: InstrumentJobAnnotationSyncService
    let metadataColumnSync: MetadataColumnSyncService
    let metadataColumnTemplateSync: MetadataColumnTemplateSyncService
    let favouriteMetadataOptionSync: FavouriteMetadataOptionSyncService
    let annotationFolderSync: AnnotationFolderSyncService
    let outboxSync: OutboxService
    let localNotebookImportSync: LocalNotebookImportService
    let timeKeeperSync: TimeKeeperSyncService
    let maintenanceLogSync: MaintenanceLogSyncService
    let stepVariationSync: StepVariationSyncService
    let protocolRatingSync: ProtocolRatingSyncService
    let storedReagentAnnotationSync: StoredReagentAnnotationSyncService
    let reagentSubscriptionSync: ReagentSubscriptionSyncService
    let samplePoolSync: SamplePoolSyncService
    let metadataTableSync: MetadataTableSyncService
    let ontologySearchSync: OnlineOntologySearchService
    let userProfileSync: UserProfileSyncService
    let deviceTokenSync: DeviceTokenSyncService
    let asyncTaskSync: AsyncTaskSyncService
}

@Observable
@MainActor
final class AppSession {
    enum ActiveContext: Equatable {
        case none
        case standalone
        case instance(KnownInstance)

        var knownInstance: KnownInstance? {
            if case .instance(let instance) = self { return instance }
            return nil
        }
    }

    private(set) var activeContext: ActiveContext
    private(set) var knownInstances: [KnownInstance]
    private(set) var baseURL: URL?
    private(set) var deviceToken: String?
    private(set) var currentUserID: Int64?
    private(set) var isStaff: Bool = false
    private(set) var currentUsername: String?
    private(set) var currentEmail: String?
    private(set) var currentFirstName: String?
    private(set) var currentLastName: String?
    private(set) var pendingLocalImportCount: Int?
    private(set) var isImportingLocalNotebook = false
    private(set) var isShowingOntologyPreloadPrompt = false
    private(set) var pendingDeepLink: DeepLinkTarget?
    var isShowingPushedDetail = false
    private(set) var syncProgress: SyncProgress?
    private(set) var isForceOffline = false

    var isAuthenticated: Bool { deviceToken != nil }
    var canUseApp: Bool { activeContext != .none }
    var isStandalone: Bool { activeContext == .standalone }
    var activeInstance: KnownInstance? { activeContext.knownInstance }

    private(set) var modelContainer: ModelContainer
    @ObservationIgnored var onRequestContainerSwap: ((ModelContainer) -> Void)?
    private var keychain: KeychainStore
    private var apiClient: APIClient?
    private var authManager: AuthManager?
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var transcriptionNotificationService: TranscriptionNotificationService?
    private var timeKeeperNotificationService: TimeKeeperNotificationService?
    private var asyncTaskNotificationService: AsyncTaskNotificationService?
    private let isUITesting: Bool

    private static let baseURLDefaultsKey = "cupcake.baseURL"
    private static let standaloneDefaultsKey = "cupcake.isStandalone"
    private static let currentUserIDDefaultsKey = "cupcake.currentUserID"
    private static let isStaffDefaultsKey = "cupcake.isStaff"
    private static let hasPromptedOntologyPreloadDefaultsKey = "cupcake.hasPromptedOntologyPreload"
    private static let activeContextDefaultsKey = "cupcake.activeContextIdentifier"

    static func resolveInitialContext(defaults: UserDefaults = .standard) -> ActiveContext {
        guard let identifier = defaults.string(forKey: activeContextDefaultsKey) else { return .none }
        if identifier == "standalone" { return .standalone }
        guard let uuid = UUID(uuidString: identifier),
              let instance = KnownInstanceRegistry.allInstances(defaults: defaults).first(where: { $0.id == uuid }) else {
            return .none
        }
        return .instance(instance)
    }

    static func storeFileName(for context: ActiveContext) -> String {
        switch context {
        case .none, .standalone:
            return "CupcakeStore.store"
        case .instance(let instance):
            return instance.storeFileName
        }
    }

    private static func keychain(for context: ActiveContext) -> KeychainStore {
        switch context {
        case .none, .standalone:
            return KeychainStore()
        case .instance(let instance):
            return KeychainStore(account: instance.keychainAccount)
        }
    }

    init(modelContainer: ModelContainer, activeContext: ActiveContext, isUITesting: Bool) {
        self.modelContainer = modelContainer
        self.activeContext = activeContext
        self.isUITesting = isUITesting
        self.knownInstances = KnownInstanceRegistry.allInstances()
        self.keychain = Self.keychain(for: activeContext)
        CachedSession.backfillProtocolClientIDsIfNeeded(in: modelContainer)
        loadActiveInstanceState()
        startMonitoringConnectivity()
    }

    private func loadActiveInstanceState() {
        switch activeContext {
        case .none, .standalone:
            currentUserID = nil
            isStaff = false
            currentUsername = nil
            currentEmail = nil
            currentFirstName = nil
            currentLastName = nil
            baseURL = nil
            deviceToken = nil
            apiClient = nil
            authManager = nil
        case .instance(let instance):
            deviceToken = keychain.load()
            let context = ModelContext(modelContainer)
            let metadata = (try? context.fetch(FetchDescriptor<InstanceMetadata>()))?.first
            currentUserID = metadata?.currentUserID
            isStaff = metadata?.isStaff ?? false
            currentUsername = metadata?.username
            currentEmail = metadata?.email
            currentFirstName = metadata?.firstName
            currentLastName = metadata?.lastName
            let urlString = metadata?.baseURLString ?? instance.baseURLString
            if let url = URL(string: urlString) {
                configureClient(baseURL: url)
            }
        }
    }

    private func saveActiveInstanceMetadata() {
        guard case .instance = activeContext else { return }
        let context = ModelContext(modelContainer)
        let existing = (try? context.fetch(FetchDescriptor<InstanceMetadata>()))?.first
        let metadata = existing ?? InstanceMetadata()
        if existing == nil { context.insert(metadata) }
        metadata.currentUserID = currentUserID
        metadata.isStaff = isStaff
        metadata.username = currentUsername
        metadata.email = currentEmail
        metadata.firstName = currentFirstName
        metadata.lastName = currentLastName
        metadata.baseURLString = baseURL?.absoluteString
        try? context.save()
    }

    private func startMonitoringConnectivity() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let cameBackOnline = path.status == .satisfied && self.lastPathStatus != .satisfied
                self.lastPathStatus = path.status
                if cameBackOnline {
                    await self.replayOutbox()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "cupcake.connectivity"))
        pathMonitor = monitor
    }

    func setForceOffline(_ value: Bool) async {
        isForceOffline = value
        await apiClient?.setForceOffline(value)
        if !value {
            await replayOutbox()
        }
    }

    func replayOutbox() async {
        guard isAuthenticated else { return }
        await makeSyncServices().outboxSync.replayPending(onProgress: { [weak self] progress in
            self?.syncProgress = progress
        })
        syncProgress = nil
    }

    func syncAll() async throws {
        guard isAuthenticated else { return }
        defer { syncProgress = nil }
        let services = makeSyncServices()
        await replayOutbox()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling protocols…")
        try await services.protocolSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling sessions…")
        try await services.sessionSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling step annotations…")
        try await services.stepAnnotationSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling session annotations…")
        try await services.sessionAnnotationSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling step reagents…")
        try await services.stepReagentSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling storage locations…")
        try await services.inventorySync.refetchStorageObjects()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling reagents…")
        try await services.inventorySync.refetchReagents()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling stored reagents…")
        try await services.inventorySync.refetchStoredReagents()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling reagent actions…")
        try await services.inventorySync.refetchReagentActions()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling instruments…")
        try await services.instrumentSync.refetchInstruments()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling instrument bookings…")
        try await services.instrumentSync.refetchInstrumentUsage()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling projects…")
        try await services.projectSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling jobs…")
        try await services.instrumentJobSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling lab groups…")
        try await services.labGroupSync.refetchAll()
        syncProgress = SyncProgress(direction: .pull, label: "Pulling table templates…")
        try await services.metadataTableTemplateSync.refetchAll()
    }

    private func configureClient(baseURL: URL) {
        self.baseURL = baseURL
        let client = APIClient(baseURL: baseURL)
        apiClient = client
        authManager = AuthManager(authService: AuthService(apiClient: client), keychain: keychain)
        transcriptionNotificationService = nil
        timeKeeperNotificationService = nil
        asyncTaskNotificationService = nil
        if isForceOffline {
            Task { await client.setForceOffline(true) }
        }
    }

    func transcriptionEvents() async -> AsyncStream<TranscriptionNotificationService.Event> {
        guard let client = apiClient else {
            return AsyncStream { $0.finish() }
        }
        let tokenSnapshot = deviceToken
        let service = transcriptionNotificationService ?? TranscriptionNotificationService(apiClient: client, deviceToken: { tokenSnapshot })
        transcriptionNotificationService = service
        return await service.subscribe()
    }

    func timeKeeperEvents() async -> AsyncStream<TimeKeeperNotificationService.Event> {
        guard let client = apiClient else {
            return AsyncStream { $0.finish() }
        }
        let tokenSnapshot = deviceToken
        let service = timeKeeperNotificationService ?? TimeKeeperNotificationService(apiClient: client, deviceToken: { tokenSnapshot })
        timeKeeperNotificationService = service
        return await service.subscribe()
    }

    func asyncTaskEvents() async -> AsyncStream<AsyncTaskNotificationService.Event> {
        guard let client = apiClient else {
            return AsyncStream { $0.finish() }
        }
        let tokenSnapshot = deviceToken
        let service = asyncTaskNotificationService ?? AsyncTaskNotificationService(apiClient: client, deviceToken: { tokenSnapshot })
        asyncTaskNotificationService = service
        return await service.subscribe()
    }

    private func persistActiveContext() {
        switch activeContext {
        case .none:
            UserDefaults.standard.removeObject(forKey: Self.activeContextDefaultsKey)
        case .standalone:
            UserDefaults.standard.set("standalone", forKey: Self.activeContextDefaultsKey)
        case .instance(let instance):
            UserDefaults.standard.set(instance.id.uuidString, forKey: Self.activeContextDefaultsKey)
        }
    }

    private func resolveOrCreateInstance(baseURLString: String) -> KnownInstance {
        if let existing = knownInstances.first(where: { $0.baseURLString == baseURLString }) {
            return existing
        }
        let label = URL(string: baseURLString)?.host ?? baseURLString
        return KnownInstance(label: label, baseURLString: baseURLString)
    }

    private func recordSuccessfulSignIn(for instance: KnownInstance, username: String?) {
        var updated = instance
        if let username {
            updated.lastUsername = username
        }
        updated.lastSignedInAt = Date()
        if let index = knownInstances.firstIndex(where: { $0.id == instance.id }) {
            knownInstances[index] = updated
        }
        if activeContext.knownInstance?.id == instance.id {
            activeContext = .instance(updated)
        }
        KnownInstanceRegistry.update(updated)
    }

    func switchToInstance(_ instance: KnownInstance) {
        keychain = Self.keychain(for: .instance(instance))
        if let url = URL(string: instance.baseURLString) {
            configureClient(baseURL: url)
        }
        commitActiveInstance(instance)
    }

    private func commitActiveInstance(_ instance: KnownInstance) {
        if !knownInstances.contains(where: { $0.id == instance.id }) {
            knownInstances.append(instance)
            KnownInstanceRegistry.add(instance)
        }
        let container = CupcakeApp.makeCupcakeStore(storeFileName: instance.storeFileName, inMemoryOnly: isUITesting)
        activeContext = .instance(instance)
        modelContainer = container
        persistActiveContext()
        loadActiveInstanceState()
        Task { @MainActor [onRequestContainerSwap] in
            onRequestContainerSwap?(container)
        }
    }

    func leaveActiveInstance() {
        activeContext = .none
        keychain = Self.keychain(for: .none)
        let container = isUITesting ? modelContainer : CupcakeApp.makeCupcakeStore(storeFileName: "CupcakeStore.store", inMemoryOnly: isUITesting)
        modelContainer = container
        persistActiveContext()
        loadActiveInstanceState()
        onRequestContainerSwap?(container)
    }

    func signOutActiveInstance() async {
        guard case .instance = activeContext else { return }
        await authManager?.signOut()
        deviceToken = nil
        currentUserID = nil
        isStaff = false
        currentUsername = nil
        currentEmail = nil
        currentFirstName = nil
        currentLastName = nil
        saveActiveInstanceMetadata()
    }

    func removeInstance(_ instance: KnownInstance) {
        if activeContext.knownInstance?.id == instance.id {
            leaveActiveInstance()
        }
        knownInstances.removeAll { $0.id == instance.id }
        KnownInstanceRegistry.remove(id: instance.id)
        KeychainStore(account: instance.keychainAccount).delete()
        let storeURL = CupcakeApp.applicationSupportDirectory.appendingPathComponent(instance.storeFileName)
        try? FileManager.default.removeItem(at: storeURL)
    }

    func hasUnsyncedOutboxEntries(for instance: KnownInstance) -> Bool {
        let container: ModelContainer
        if activeContext.knownInstance?.id == instance.id {
            container = modelContainer
        } else {
            container = CupcakeApp.makeCupcakeStore(storeFileName: instance.storeFileName, inMemoryOnly: isUITesting)
        }
        let context = ModelContext(container)
        let count = (try? context.fetchCount(FetchDescriptor<OutboxEntry>())) ?? 0
        return count > 0
    }

    func signIn(serverURLString: String, username: String, password: String) async throws {
        guard let url = URL(string: serverURLString) else {
            throw AppSessionError.invalidServerURL
        }
        let instance = resolveOrCreateInstance(baseURLString: serverURLString)
        keychain = Self.keychain(for: .instance(instance))
        configureClient(baseURL: url)
        let result = try await authManager?.signIn(username: username, password: password, deviceLabel: Self.deviceLabel)
        commitActiveInstance(instance)
        if let userID = result?.deviceToken.user {
            currentUserID = Int64(userID)
        }
        isStaff = result?.user.isStaff ?? false
        currentUsername = result?.user.username
        currentEmail = result?.user.email
        currentFirstName = result?.user.firstName
        currentLastName = result?.user.lastName
        saveActiveInstanceMetadata()
        recordSuccessfulSignIn(for: instance, username: username)
    }

    func refreshProfile() async {
        guard let currentUserID else { return }
        guard let profile = try? await makeSyncServices().userProfileSync.fetchProfile(userID: currentUserID) else { return }
        currentUsername = profile.username
        currentEmail = profile.email
        currentFirstName = profile.firstName
        currentLastName = profile.lastName
        isStaff = profile.isStaff
        saveActiveInstanceMetadata()
    }

    func updateProfile(firstName: String?, lastName: String?, email: String?, currentPassword: String?) async throws {
        let profile = try await makeSyncServices().userProfileSync.updateProfile(
            firstName: firstName,
            lastName: lastName,
            email: email,
            currentPassword: currentPassword
        )
        currentUsername = profile.username
        currentEmail = profile.email
        currentFirstName = profile.firstName
        currentLastName = profile.lastName
        saveActiveInstanceMetadata()
    }

    func changePassword(currentPassword: String, newPassword: String, confirmPassword: String) async throws {
        try await makeSyncServices().userProfileSync.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
            confirmPassword: confirmPassword
        )
    }

    func checkForLocalRecordsToImport() async {
        let count = (try? await makeSyncServices().localNotebookImportSync.countLocalOnlyRecords()) ?? 0
        if count > 0 {
            pendingLocalImportCount = count
        }
    }

    func importLocalNotebook() async {
        isImportingLocalNotebook = true
        defer {
            isImportingLocalNotebook = false
            pendingLocalImportCount = nil
        }
        await makeSyncServices().localNotebookImportSync.importAll()
    }

    func dismissLocalImportPrompt() {
        pendingLocalImportCount = nil
    }

    func checkForOntologyPreloadPrompt() {
        guard !UserDefaults.standard.bool(forKey: Self.hasPromptedOntologyPreloadDefaultsKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasPromptedOntologyPreloadDefaultsKey)
        isShowingOntologyPreloadPrompt = true
    }

    func dismissOntologyPreloadPrompt() {
        isShowingOntologyPreloadPrompt = false
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "cupcake", url.host == "annotation",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sessionServerIDString = components.queryItems?.first(where: { $0.name == "session" })?.value,
              let sessionServerID = Int64(sessionServerIDString) else { return }
        let annotationServerID = components.queryItems?.first(where: { $0.name == "id" })?.value.flatMap(Int64.init)

        let context = ModelContext(modelContainer)
        guard let session = try? context.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == sessionServerID })
        ).first else { return }

        pendingDeepLink = DeepLinkTarget(sessionClientID: session.clientID, annotationServerID: annotationServerID)
    }

    func consumeDeepLink() -> DeepLinkTarget? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }

    func signInWithORCID(serverURLString: String) async throws {
        guard let url = URL(string: serverURLString) else {
            throw AppSessionError.invalidServerURL
        }
        let instance = resolveOrCreateInstance(baseURLString: serverURLString)
        keychain = Self.keychain(for: .instance(instance))
        configureClient(baseURL: url)
        guard let authManager else {
            throw AppSessionError.invalidServerURL
        }

        let loginURL = authManager.orcidLoginURL()
        let callbackURL = try await presentORCIDSession(url: loginURL)

        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let authCode = components.queryItems?.first(where: { $0.name == "auth_code" })?.value
        else {
            let errorMessage = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            throw AppSessionError.orcidSignInFailed(errorMessage ?? "No auth code returned")
        }

        let result = try await authManager.completeORCIDSignIn(authCode: authCode, deviceLabel: Self.deviceLabel)
        commitActiveInstance(instance)
        currentUserID = Int64(result.deviceToken.user)
        isStaff = result.user.isStaff
        currentUsername = result.user.username
        currentEmail = result.user.email
        currentFirstName = result.user.firstName
        currentLastName = result.user.lastName
        saveActiveInstanceMetadata()
        recordSuccessfulSignIn(for: instance, username: result.user.username)
    }

    private var activeORCIDSession: ASWebAuthenticationSession?
    private var activeORCIDContextProvider: ORCIDPresentationContextProvider?

    private func presentORCIDSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let contextProvider = ORCIDPresentationContextProvider()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "cupcake") { [weak self] callbackURL, error in
                self?.activeORCIDSession = nil
                self?.activeORCIDContextProvider = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AppSessionError.orcidSignInFailed("Cancelled"))
                }
            }
            session.presentationContextProvider = contextProvider
            activeORCIDSession = session
            activeORCIDContextProvider = contextProvider
            let started = session.start()
            if !started {
                activeORCIDSession = nil
                activeORCIDContextProvider = nil
                continuation.resume(throwing: AppSessionError.orcidSignInFailed("ASWebAuthenticationSession.start() returned false"))
            }
        }
    }

    func signOut() async {
        await signOutActiveInstance()
        leaveActiveInstance()
    }

    func continueOffline() {
        let container = isUITesting ? modelContainer : CupcakeApp.makeCupcakeStore(storeFileName: "CupcakeStore.store", inMemoryOnly: isUITesting)
        activeContext = .standalone
        modelContainer = container
        keychain = Self.keychain(for: .standalone)
        persistActiveContext()
        loadActiveInstanceState()
        onRequestContainerSwap?(container)
    }

    func exitStandalone() {
        leaveActiveInstance()
    }

    func makeSyncServices() -> SyncServices {
        let client = apiClient ?? APIClient(baseURL: Self.placeholderBaseURL)
        let tokenSnapshot = deviceToken
        let protocolSync = ProtocolSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let sessionSync = SessionSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let stepReagentSync = StepReagentSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let inventorySync = InventorySyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let instrumentSync = InstrumentSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let projectSync = ProjectSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let labGroupSync = LabGroupSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let metadataTableTemplateSync = MetadataTableTemplateSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let instrumentJobAnnotationSync = InstrumentJobAnnotationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }, instrumentJobSync: instrumentJobSync)
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let metadataColumnTemplateSync = MetadataColumnTemplateSyncService(apiClient: client, deviceToken: { tokenSnapshot })
        let favouriteMetadataOptionSync = FavouriteMetadataOptionSyncService(apiClient: client, deviceToken: { tokenSnapshot })
        let annotationFolderSync = AnnotationFolderSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let outboxSync = OutboxService(
            modelContainer: modelContainer,
            protocolSync: protocolSync,
            sessionSync: sessionSync,
            stepReagentSync: stepReagentSync,
            stepAnnotationSync: stepAnnotationSync,
            sessionAnnotationSync: sessionAnnotationSync,
            inventorySync: inventorySync,
            instrumentSync: instrumentSync,
            projectSync: projectSync,
            instrumentJobSync: instrumentJobSync
        )
        let localNotebookImportSync = LocalNotebookImportService(modelContainer: modelContainer, outboxSync: outboxSync)
        let timeKeeperSync = TimeKeeperSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let maintenanceLogSync = MaintenanceLogSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let stepVariationSync = StepVariationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let protocolRatingSync = ProtocolRatingSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let storedReagentAnnotationSync = StoredReagentAnnotationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let reagentSubscriptionSync = ReagentSubscriptionSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let samplePoolSync = SamplePoolSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        let metadataTableSync = MetadataTableSyncService(apiClient: client, deviceToken: { tokenSnapshot })
        let ontologySearchSync = OnlineOntologySearchService(metadataColumnSync: metadataColumnSync)
        let userProfileSync = UserProfileSyncService(apiClient: client, deviceToken: { tokenSnapshot })
        let deviceTokenSync = DeviceTokenSyncService(apiClient: client, deviceToken: { tokenSnapshot })
        let asyncTaskSync = AsyncTaskSyncService(apiClient: client, deviceToken: { tokenSnapshot })
        return SyncServices(
            protocolSync: protocolSync,
            sessionSync: sessionSync,
            stepAnnotationSync: stepAnnotationSync,
            sessionAnnotationSync: sessionAnnotationSync,
            inventorySync: inventorySync,
            instrumentSync: instrumentSync,
            stepReagentSync: stepReagentSync,
            projectSync: projectSync,
            instrumentJobSync: instrumentJobSync,
            labGroupSync: labGroupSync,
            metadataTableTemplateSync: metadataTableTemplateSync,
            instrumentJobAnnotationSync: instrumentJobAnnotationSync,
            metadataColumnSync: metadataColumnSync,
            metadataColumnTemplateSync: metadataColumnTemplateSync,
            favouriteMetadataOptionSync: favouriteMetadataOptionSync,
            annotationFolderSync: annotationFolderSync,
            outboxSync: outboxSync,
            localNotebookImportSync: localNotebookImportSync,
            timeKeeperSync: timeKeeperSync,
            maintenanceLogSync: maintenanceLogSync,
            stepVariationSync: stepVariationSync,
            protocolRatingSync: protocolRatingSync,
            storedReagentAnnotationSync: storedReagentAnnotationSync,
            reagentSubscriptionSync: reagentSubscriptionSync,
            samplePoolSync: samplePoolSync,
            metadataTableSync: metadataTableSync,
            ontologySearchSync: ontologySearchSync,
            userProfileSync: userProfileSync,
            deviceTokenSync: deviceTokenSync,
            asyncTaskSync: asyncTaskSync
        )
    }

    private static let placeholderBaseURL = URL(string: "https://cupcake.invalid/api/v1/")!

    static func resetPersistedStateForUITesting() {
        UserDefaults.standard.removeObject(forKey: baseURLDefaultsKey)
        UserDefaults.standard.removeObject(forKey: standaloneDefaultsKey)
        UserDefaults.standard.removeObject(forKey: currentUserIDDefaultsKey)
        UserDefaults.standard.removeObject(forKey: isStaffDefaultsKey)
        UserDefaults.standard.removeObject(forKey: activeContextDefaultsKey)
        UserDefaults.standard.removeObject(forKey: hasPromptedOntologyPreloadDefaultsKey)
        KnownInstanceRegistry.removeAll()
        KeychainStore().delete()
    }

    static func suppressOntologyPreloadPromptForUITesting() {
        UserDefaults.standard.set(true, forKey: hasPromptedOntologyPreloadDefaultsKey)
    }

    private static var deviceLabel: String {
        #if os(iOS)
        "Cupcake iOS (\(ProcessInfo.processInfo.hostName))"
        #else
        "Cupcake Mac (\(ProcessInfo.processInfo.hostName))"
        #endif
    }
}

enum AppSessionError: LocalizedError {
    case invalidServerURL
    case orcidSignInFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "That server URL doesn't look valid."
        case .orcidSignInFailed(let reason):
            reason
        }
    }
}
