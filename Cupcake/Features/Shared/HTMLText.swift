import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders server-stored HTML descriptions/annotations, force-substituting a system font while preserving bold/italic.
struct HTMLText: View {
    let html: String

    var body: some View {
        if let attributed = Self.attributedString(from: html) {
            Text(attributed)
        } else {
            Text(html)
        }
    }

    /// Skips the expensive HTML-import pipeline entirely for plain text with no `<` at all.
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

    /// Strips markup for contexts that need a plain `String` rather than a styled `View`.
    static func plainText(from html: String) -> String {
        attributedString(from: html).map { String($0.characters) } ?? html
    }
}
