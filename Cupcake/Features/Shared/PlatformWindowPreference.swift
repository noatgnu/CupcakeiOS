import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Whether a management screen should open as its own window instead of a sheet.
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
}
