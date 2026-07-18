#if os(macOS)
import AppKit

final class MacWindowPlacementFixer: NSObject, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            Self.clampToVisibleScreen(window)
        }
    }

    private static func clampToVisibleScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var frame = window.frame

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
        }
        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
        }
        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }

        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }
}
#endif
