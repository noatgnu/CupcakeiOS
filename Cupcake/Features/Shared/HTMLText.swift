import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct HTMLText: View {
    let html: String

    @AppStorage("stepDetailUseCustomFontSize") private var useCustomFontSize = false
    @AppStorage("stepDetailFontSize") private var customFontSize: Double = Double(HTMLText.defaultBodyPointSize)

    @State private var parsed: AttributedString?

    private var resolvedPointSize: CGFloat {
        useCustomFontSize && customFontSize > 0 ? CGFloat(customFontSize) : Self.defaultBodyPointSize
    }

    private var cacheKey: String {
        "\(resolvedPointSize)|\(html)"
    }

    var body: some View {
        Group {
            if let resolved = parsed ?? Self.cachedAttributedString(forKey: cacheKey) {
                Text(resolved)
            } else {
                Text(Self.lightweightPlainText(from: html))
                    .font(.system(size: resolvedPointSize))
            }
        }
        .task(id: cacheKey) {
            guard html.contains("<"), Self.cachedAttributedString(forKey: cacheKey) == nil else { return }
            parsed = await Self.parseAndCache(html: html, pointSize: resolvedPointSize, cacheKey: cacheKey)
        }
    }

    private static let cache = NSCache<NSString, NSAttributedString>()

    private static func cachedAttributedString(forKey key: String) -> AttributedString? {
        guard let cached = cache.object(forKey: key as NSString) else { return nil }
        return AttributedString(cached)
    }

    @MainActor
    private static func parseAndCache(html: String, pointSize: CGFloat, cacheKey: String) async -> AttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        guard let nsAttributed = try? NSMutableAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }

        let fullRange = NSRange(location: 0, length: nsAttributed.length)
        nsAttributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            nsAttributed.addAttribute(.font, value: Self.systemFont(matching: value as? PlatformFont, pointSize: pointSize), range: range)
        }
        nsAttributed.removeAttribute(.foregroundColor, range: fullRange)
        nsAttributed.addAttribute(.foregroundColor, value: Self.labelColor, range: fullRange)
        cache.setObject(nsAttributed, forKey: cacheKey as NSString)
        return AttributedString(nsAttributed)
    }

    #if os(iOS)
    private typealias PlatformFont = UIFont
    #elseif os(macOS)
    private typealias PlatformFont = NSFont
    #endif

    #if os(iOS)
    static let defaultBodyPointSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize
    private static let labelColor: UIColor = .label
    #elseif os(macOS)
    static let defaultBodyPointSize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize
    private static let labelColor: NSColor = .labelColor
    #endif

    private static func systemFont(matching originalFont: PlatformFont?, pointSize: CGFloat) -> PlatformFont {
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

    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]+>", options: [])

    static func lightweightPlainText(from html: String) -> String {
        guard html.contains("<") else { return html }
        let range = NSRange(html.startIndex..., in: html)
        let stripped = tagPattern.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func plainText(from html: String) -> String {
        guard html.contains("<") else { return html }
        guard let data = html.data(using: .utf8),
              let nsAttributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else { return html }
        return nsAttributed.string
    }
}
