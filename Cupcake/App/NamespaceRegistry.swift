import CupcakeModels
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum PendingLaunchAction {
    case knownInstance(KnownInstance)
    case signIn(serverURLString: String, username: String, password: String)
    case signInWithORCID(serverURLString: String)
    case continueOffline
}

@MainActor
final class NamespaceRegistry {
    static let shared = NamespaceRegistry()

    private var sessions: [UUID: AppSession] = [:]
    private var pendingLaunchActionQueue: [PendingLaunchAction] = []
    private(set) var mainWindowNamespaceIDsByFocusOrder: [UUID] = []
    #if os(macOS)
    private var auxiliaryWindowsByKey: [String: NSWindow] = [:]
    #endif

    private init() {}

    func register(_ session: AppSession, for id: UUID) {
        sessions[id] = session
    }

    func session(for id: UUID) -> AppSession? {
        sessions[id]
    }

    func unregister(_ id: UUID) {
        sessions.removeValue(forKey: id)
        mainWindowNamespaceIDsByFocusOrder.removeAll { $0 == id }
    }

    func enqueuePendingLaunchAction(_ action: PendingLaunchAction) {
        pendingLaunchActionQueue.append(action)
    }

    func dequeuePendingLaunchAction() -> PendingLaunchAction? {
        pendingLaunchActionQueue.isEmpty ? nil : pendingLaunchActionQueue.removeFirst()
    }

    func noteMainWindowFocused(namespaceID: UUID) {
        mainWindowNamespaceIDsByFocusOrder.removeAll { $0 == namespaceID }
        mainWindowNamespaceIDsByFocusOrder.insert(namespaceID, at: 0)
    }

    var focusedOrFirstNamespaceID: UUID? {
        mainWindowNamespaceIDsByFocusOrder.first ?? sessions.keys.first
    }

    var hasOtherOpenMainWindows: Bool {
        sessions.count > 1
    }

    #if os(macOS)
    func registerAuxiliaryWindow(_ window: NSWindow, key: String) {
        auxiliaryWindowsByKey[key] = window
    }

    func unregisterAuxiliaryWindow(key: String) {
        auxiliaryWindowsByKey.removeValue(forKey: key)
    }

    func auxiliaryWindow(key: String) -> NSWindow? {
        auxiliaryWindowsByKey[key]
    }
    #endif
}

private struct NamespaceIDKey: EnvironmentKey {
    static let defaultValue = UUID()
}

extension EnvironmentValues {
    var namespaceID: UUID {
        get { self[NamespaceIDKey.self] }
        set { self[NamespaceIDKey.self] = newValue }
    }
}

struct AuxiliaryWindowID: Codable, Hashable {
    let namespaceID: UUID
}

#if os(macOS)
struct MainWindowFocusTracker: NSViewRepresentable {
    let namespaceID: UUID

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                Task { @MainActor in
                    NamespaceRegistry.shared.noteMainWindowFocused(namespaceID: namespaceID)
                }
            }
            NamespaceRegistry.shared.noteMainWindowFocused(namespaceID: namespaceID)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct WindowRegistrar: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NamespaceRegistry.shared.registerAuxiliaryWindow(window, key: key)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                Task { @MainActor in
                    NamespaceRegistry.shared.unregisterAuxiliaryWindow(key: key)
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
