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
}

@Observable
@MainActor
final class AppSession {
    private(set) var baseURL: URL?
    private(set) var deviceToken: String?
    private(set) var isStandalone: Bool
    private(set) var currentUserID: Int64?
    private(set) var isStaff: Bool = false
    private(set) var pendingLocalImportCount: Int?
    private(set) var isImportingLocalNotebook = false
    private(set) var pendingDeepLink: DeepLinkTarget?

    var isAuthenticated: Bool { deviceToken != nil }
    var canUseApp: Bool { isAuthenticated || isStandalone }

    private let modelContainer: ModelContainer
    private let keychain = KeychainStore()
    private var apiClient: APIClient?
    private var authManager: AuthManager?
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var transcriptionNotificationService: TranscriptionNotificationService?
    private var timeKeeperNotificationService: TimeKeeperNotificationService?

    private static let baseURLDefaultsKey = "cupcake.baseURL"
    private static let standaloneDefaultsKey = "cupcake.isStandalone"
    private static let currentUserIDDefaultsKey = "cupcake.currentUserID"
    private static let isStaffDefaultsKey = "cupcake.isStaff"

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        CachedSession.backfillProtocolClientIDsIfNeeded(in: modelContainer)
        isStandalone = UserDefaults.standard.bool(forKey: Self.standaloneDefaultsKey)
        if let savedURLString = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey),
           let url = URL(string: savedURLString) {
            configureClient(baseURL: url)
            deviceToken = keychain.load()
            if deviceToken != nil, UserDefaults.standard.object(forKey: Self.currentUserIDDefaultsKey) != nil {
                currentUserID = Int64(UserDefaults.standard.integer(forKey: Self.currentUserIDDefaultsKey))
            }
            if deviceToken != nil {
                isStaff = UserDefaults.standard.bool(forKey: Self.isStaffDefaultsKey)
            }
        }
        startMonitoringConnectivity()
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

    func replayOutbox() async {
        guard isAuthenticated else { return }
        await makeSyncServices().outboxSync.replayPending()
    }

    func syncAll() async throws {
        guard isAuthenticated else { return }
        let services = makeSyncServices()
        await replayOutbox()
        try await services.protocolSync.refetchAll()
        try await services.sessionSync.refetchAll()
        try await services.stepReagentSync.refetchAll()
        try await services.inventorySync.refetchStorageObjects()
        try await services.inventorySync.refetchReagents()
        try await services.inventorySync.refetchStoredReagents()
        try await services.inventorySync.refetchReagentActions()
        try await services.instrumentSync.refetchInstruments()
        try await services.instrumentSync.refetchInstrumentUsage()
        try await services.projectSync.refetchAll()
        try await services.instrumentJobSync.refetchAll()
        try await services.labGroupSync.refetchAll()
        try await services.metadataTableTemplateSync.refetchAll()
    }

    private func configureClient(baseURL: URL) {
        self.baseURL = baseURL
        let client = APIClient(baseURL: baseURL)
        apiClient = client
        authManager = AuthManager(authService: AuthService(apiClient: client), keychain: keychain)
        transcriptionNotificationService = nil
        timeKeeperNotificationService = nil
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

    func signIn(serverURLString: String, username: String, password: String) async throws {
        guard let url = URL(string: serverURLString) else {
            throw AppSessionError.invalidServerURL
        }
        configureClient(baseURL: url)
        let result = try await authManager?.signIn(username: username, password: password, deviceLabel: Self.deviceLabel)
        UserDefaults.standard.set(serverURLString, forKey: Self.baseURLDefaultsKey)
        deviceToken = keychain.load()
        isStandalone = false
        UserDefaults.standard.set(false, forKey: Self.standaloneDefaultsKey)
        if let userID = result?.deviceToken.user {
            currentUserID = Int64(userID)
            UserDefaults.standard.set(userID, forKey: Self.currentUserIDDefaultsKey)
        }
        isStaff = result?.isStaff ?? false
        UserDefaults.standard.set(isStaff, forKey: Self.isStaffDefaultsKey)
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
        UserDefaults.standard.set(serverURLString, forKey: Self.baseURLDefaultsKey)
        deviceToken = keychain.load()
        isStandalone = false
        UserDefaults.standard.set(false, forKey: Self.standaloneDefaultsKey)
        currentUserID = Int64(result.deviceToken.user)
        UserDefaults.standard.set(result.deviceToken.user, forKey: Self.currentUserIDDefaultsKey)
        isStaff = result.isStaff
        UserDefaults.standard.set(isStaff, forKey: Self.isStaffDefaultsKey)
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
        await authManager?.signOut()
        deviceToken = nil
        currentUserID = nil
        UserDefaults.standard.removeObject(forKey: Self.currentUserIDDefaultsKey)
        isStaff = false
        UserDefaults.standard.removeObject(forKey: Self.isStaffDefaultsKey)
    }

    func continueOffline() {
        isStandalone = true
        UserDefaults.standard.set(true, forKey: Self.standaloneDefaultsKey)
    }

    func exitStandalone() {
        isStandalone = false
        UserDefaults.standard.set(false, forKey: Self.standaloneDefaultsKey)
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
            metadataTableSync: metadataTableSync
        )
    }

    private static let placeholderBaseURL = URL(string: "https://cupcake.invalid/api/v1/")!

    static func resetPersistedStateForUITesting() {
        UserDefaults.standard.removeObject(forKey: baseURLDefaultsKey)
        UserDefaults.standard.removeObject(forKey: standaloneDefaultsKey)
        KeychainStore().delete()
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
