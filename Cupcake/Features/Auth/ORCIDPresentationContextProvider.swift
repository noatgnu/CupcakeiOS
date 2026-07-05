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
        // `keyWindow`/`mainWindow` can both be nil at this exact moment (e.g. driven by
        // XCUITest, where the window may not hold key status the way normal interactive use
        // does) — fall back to any visible, on-screen window before the last-resort phantom
        // anchor, which would make the sheet silently fail to appear at all.
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first { $0.isVisible }
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #endif
    }
}
