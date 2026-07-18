import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct HTMLText: View {
    let html: String

    @State private var parsed: AttributedString?

    var body: some View {
        Group {
            if let resolved = parsed ?? Self.cachedAttributedString(from: html) {
                Text(resolved)
            } else {
                Text(html)
            }
        }
        .task(id: html) {
            guard html.contains("<"), Self.cachedAttributedString(from: html) == nil else { return }
            parsed = await Self.parseAndCache(html: html)
        }
    }

    private static let cache = NSCache<NSString, NSAttributedString>()

    private static func cachedAttributedString(from html: String) -> AttributedString? {
        guard let cached = cache.object(forKey: html as NSString) else { return nil }
        return AttributedString(cached)
    }

    @MainActor
    private static func parseAndCache(html: String) async -> AttributedString? {
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
        cache.setObject(nsAttributed, forKey: html as NSString)
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

    static func plainText(from html: String) -> String {
        guard html.contains("<") else { return html }
        if let cached = cachedAttributedString(from: html) {
            return String(cached.characters)
        }
        guard let data = html.data(using: .utf8),
              let nsAttributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else { return html }
        return nsAttributed.string
    }
}
