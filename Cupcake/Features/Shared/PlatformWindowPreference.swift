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
    static func openOrFocusWindow(id: String, namespaceID: UUID, using openWindow: OpenWindowAction) {
        #if os(macOS)
        if let existing = NamespaceRegistry.shared.auxiliaryWindow(key: "\(id)|\(namespaceID)") {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        #endif
        openWindow(id: id, value: AuxiliaryWindowID(namespaceID: namespaceID))
    }
}

private struct CloseWindowToolbarModifier: ViewModifier {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

    private func close() {
        if PlatformWindowPreference.prefersSeparateWindow {
            dismissWindow()
        } else {
            dismiss()
        }
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        if PlatformWindowPreference.prefersSeparateWindow {
            content.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: close)
                        .accessibilityIdentifier("doneButton_\(id)")
                }
            }
        } else {
            content
        }
        #endif
    }
}

extension View {
    func closableWindowToolbar(id: String) -> some View {
        modifier(CloseWindowToolbarModifier(id: id))
    }
}
