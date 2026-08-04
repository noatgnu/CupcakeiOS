#if os(iOS)
import UIKit

final class UITestingSceneCleaner: NSObject, UIApplicationDelegate {
    private var hasCleanedStaleSessions = false

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state"), !hasCleanedStaleSessions else { return }
        hasCleanedStaleSessions = true
        let activeSessions = Set(application.connectedScenes.map { $0.session })
        for session in application.openSessions where !activeSessions.contains(session) {
            application.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
        }
    }
}
#endif
