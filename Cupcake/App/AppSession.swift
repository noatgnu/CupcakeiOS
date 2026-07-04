import CupcakeAuth
import CupcakeNetworking
import CupcakeSync
import Foundation
import Network
import SwiftData
import SwiftUI

/// Bundles the sync-service actors a view needs for one screen. Constructed fresh on demand
/// (see `AppSession.makeSyncServices()`) rather than held long-lived, since the device token it
/// captures is a plain value snapshot, not a live reference. In standalone mode (or before any
/// server has been configured) every service still constructs successfully — their online calls
/// just no-op or fall back to a local-only path, since none of them have a real `DeviceToken`.
struct SyncServices {
    let protocolSync: ProtocolSyncService
    let sessionSync: SessionSyncService
    let stepAnnotationSync: StepAnnotationSyncService
    let sessionAnnotationSync: SessionAnnotationSyncService
    let inventorySync: InventorySyncService
    let instrumentSync: InstrumentSyncService
    /// Run `stepReagentSync` after `protocolSync.refetchAll()` — it resolves each step-reagent's
    /// `stepClientID` by looking up the step's cached `serverID`, which only exists once the
    /// protocol tree has synced.
    let stepReagentSync: StepReagentSyncService
    let outboxSync: OutboxService
}

/// Owns the server connection + auth state for the whole app. A fresh `APIClient`/`AuthManager`
/// pair is (re)built whenever the configured server URL changes — there's exactly one backend
/// this app talks to at a time in v1.
///
/// Standalone mode (§4.3 of the design doc) is a distinct state from "online but signed out" —
/// entered explicitly via `continueOffline()` when the user has never configured a backend at
/// all. It's the state that makes the app testable without any live server or credentials: the
/// local protocol/session/annotation creation flows work identically whether or not a server was
/// ever configured, since every cached model's real identity is a client-generated UUID, not a
/// server-assigned one (see the `Cached*` model docs).
@Observable
@MainActor
final class AppSession {
    private(set) var baseURL: URL?
    private(set) var deviceToken: String?
    private(set) var isStandalone: Bool

    var isAuthenticated: Bool { deviceToken != nil }
    var canUseApp: Bool { isAuthenticated || isStandalone }

    private let modelContainer: ModelContainer
    private let keychain = KeychainStore()
    private var apiClient: APIClient?
    private var authManager: AuthManager?
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?

    private static let baseURLDefaultsKey = "cupcake.baseURL"
    private static let standaloneDefaultsKey = "cupcake.isStandalone"

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        isStandalone = UserDefaults.standard.bool(forKey: Self.standaloneDefaultsKey)
        if let savedURLString = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey),
           let url = URL(string: savedURLString) {
            configureClient(baseURL: url)
            deviceToken = keychain.load()
        }
        startMonitoringConnectivity()
    }

    /// Cross-platform as-is (`NWPathMonitor` isn't iOS-only) — replays any queued outbox entries
    /// the moment connectivity comes back, rather than making the user remember to retry
    /// manually. Also fires once at launch if the network is already up, to catch anything left
    /// queued from a previous offline session.
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

    /// Also callable directly for a manual "Retry Sync" action, not just the automatic
    /// reconnect trigger.
    func replayOutbox() async {
        guard isAuthenticated else { return }
        await makeSyncServices().outboxSync.replayPending()
    }

    private func configureClient(baseURL: URL) {
        self.baseURL = baseURL
        let client = APIClient(baseURL: baseURL)
        apiClient = client
        authManager = AuthManager(authService: AuthService(apiClient: client), keychain: keychain)
    }

    func signIn(serverURLString: String, username: String, password: String) async throws {
        guard let url = URL(string: serverURLString) else {
            throw AppSessionError.invalidServerURL
        }
        configureClient(baseURL: url)
        try await authManager?.signIn(username: username, password: password, deviceLabel: Self.deviceLabel)
        UserDefaults.standard.set(serverURLString, forKey: Self.baseURLDefaultsKey)
        deviceToken = keychain.load()
        isStandalone = false
        UserDefaults.standard.set(false, forKey: Self.standaloneDefaultsKey)
    }

    func signOut() async {
        await authManager?.signOut()
        deviceToken = nil
    }

    /// Enters standalone mode: no backend configured, no login, purely local content.
    func continueOffline() {
        isStandalone = true
        UserDefaults.standard.set(true, forKey: Self.standaloneDefaultsKey)
    }

    /// Leaves standalone mode to return to the login screen — the local content created while
    /// standalone isn't deleted (§4.3's "import my local notebook" flow reconciles it later,
    /// once that phase exists); this just stops treating the app as usable without a server.
    func exitStandalone() {
        isStandalone = false
        UserDefaults.standard.set(false, forKey: Self.standaloneDefaultsKey)
    }

    /// Always succeeds — see the type's doc comment for why a missing server/token doesn't
    /// prevent constructing these.
    func makeSyncServices() -> SyncServices {
        let client = apiClient ?? APIClient(baseURL: Self.placeholderBaseURL)
        let tokenSnapshot = deviceToken
        let protocolSync = ProtocolSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot })
        return SyncServices(
            protocolSync: protocolSync,
            sessionSync: SessionSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }),
            stepAnnotationSync: StepAnnotationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }),
            sessionAnnotationSync: SessionAnnotationSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }),
            inventorySync: InventorySyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }),
            instrumentSync: InstrumentSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }),
            stepReagentSync: StepReagentSyncService(modelContainer: modelContainer, apiClient: client, deviceToken: { tokenSnapshot }),
            outboxSync: OutboxService(modelContainer: modelContainer, protocolSync: protocolSync)
        )
    }

    private static let placeholderBaseURL = URL(string: "https://cupcake.invalid/api/v1/")!

    /// Called only from `CupcakeApp.init()` when launched with `--ui-testing-reset-state`, so
    /// UI tests get a deterministic, signed-out/non-standalone starting state regardless of
    /// whatever a previous run (or manual testing) left behind.
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

enum AppSessionError: Error {
    case invalidServerURL
}
