import SwiftUI

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum PlatformWindowPreference {
    static var prefersSeparateWindow: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    @MainActor
    static func openOrFocusWindow(id: String, using openWindow: OpenWindowAction) {
        #if os(macOS)
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.contains(id) == true }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        #endif
        openWindow(id: id)
    }
}
