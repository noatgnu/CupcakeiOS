import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Step/section/protocol descriptions and annotations authored via the reference web app's
/// rich-text editor are stored as HTML server-side, not plain text — displaying them with a
/// plain `Text(string)` shows the raw markup (`<span class="component-amount">1 mg</span>`)
/// instead of rendering it. `NSAttributedString`'s HTML import must run on the main thread
/// (Apple's own documented constraint), which is where SwiftUI view bodies already run.
///
/// `.defaultAttributes` only sets a fallback baseline — the web editor's own HTML/CSS still
/// specifies an explicit font that overrides it, so every run's font is force-substituted with
/// a system-font equivalent afterward instead (preserving bold/italic via the original font's
/// symbolic traits, not preserving the original family/size).
struct HTMLText: View {
    let html: String

    var body: some View {
        if let attributed = Self.attributedString(from: html) {
            Text(attributed)
        } else {
            Text(html)
        }
    }

    /// Locally-authored content (this app has no rich-text editor) never contains a `<` at all —
    /// skip the genuinely expensive `NSAttributedString` HTML-import pipeline entirely for it,
    /// rather than paying that cost on every render for text that was never going to need it.
    private static func attributedString(from html: String) -> AttributedString? {
        guard html.contains("<") else { return nil }
        guard let data = html.data(using: .utf8) else { return nil }
        guard let nsAttributed = try? NSMutableAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }

        let fullRange = NSRange(location: 0, length: nsAttributed.length)
        nsAttributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            nsAttributed.addAttribute(.font, value: Self.systemFont(matching: value as? PlatformFont), range: range)
        }
        return AttributedString(nsAttributed)
    }

    #if os(iOS)
    private typealias PlatformFont = UIFont
    #elseif os(macOS)
    private typealias PlatformFont = NSFont
    #endif

    private static func systemFont(matching originalFont: PlatformFont?) -> PlatformFont {
        let pointSize = originalFont?.pointSize ?? PlatformFont.systemFontSize
        #if os(iOS)
        let traits = originalFont?.fontDescriptor.symbolicTraits ?? []
        let isBold = traits.contains(.traitBold)
        let isItalic = traits.contains(.traitItalic)
        var font = isBold ? UIFont.boldSystemFont(ofSize: pointSize) : UIFont.systemFont(ofSize: pointSize)
        if isItalic, let italicDescriptor = font.fontDescriptor.withSymbolicTraits(traits.union(.traitItalic)) {
            font = UIFont(descriptor: italicDescriptor, size: pointSize)
        }
        return font
        #elseif os(macOS)
        let traits = originalFont?.fontDescriptor.symbolicTraits ?? []
        let isBold = traits.contains(.bold)
        let isItalic = traits.contains(.italic)
        let manager = NSFontManager.shared
        var font = NSFont.systemFont(ofSize: pointSize)
        if isBold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if isItalic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
        #endif
    }

    /// For contexts that need a plain `String` (navigation titles, section header text) rather
    /// than a styled `View` — strips markup instead of rendering it.
    static func plainText(from html: String) -> String {
        attributedString(from: html).map { String($0.characters) } ?? html
    }
}
