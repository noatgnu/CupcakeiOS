import AuthenticationServices

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Finds the current key/frontmost window for `ASWebAuthenticationSession` to present from.
final class ORCIDPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #elseif os(macOS)
        // Falls back to any visible window if keyWindow/mainWindow are both nil.
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first { $0.isVisible }
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #endif
    }
}
