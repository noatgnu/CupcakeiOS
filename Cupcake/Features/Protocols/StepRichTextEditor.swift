import CupcakeModels
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum RichTextHTMLCodec {
    static func attributedString(from html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
    }

    static func html(from attributedString: NSAttributedString) -> String {
        guard !attributedString.string.isEmpty else { return "" }
        guard let data = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ), let html = String(data: data, encoding: .utf8) else {
            return attributedString.string
        }
        return html
    }
}

#if os(iOS)
typealias PlatformTextView = UITextView
typealias PlatformFont = UIFont
#elseif os(macOS)
typealias PlatformTextView = NSTextView
typealias PlatformFont = NSFont
#endif

@MainActor
@Observable
final class StepRichTextEditorController {
    fileprivate weak var textView: PlatformTextView?
    fileprivate var syncHTMLFromTextView: (() -> Void)?

    func toggleBold() { toggleFontTrait(bold: true) }
    func toggleItalic() { toggleFontTrait(bold: false) }

    func toggleUnderline() {
        guard let textView, let storage = storage(of: textView) else { return }
        let range = selectedRange(of: textView)
        guard range.length > 0 else { return }
        storage.beginEditing()
        var alreadyUnderlined = true
        storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                alreadyUnderlined = false
                stop.pointee = true
            }
        }
        let newValue = alreadyUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        storage.addAttribute(.underlineStyle, value: newValue, range: range)
        storage.endEditing()
        syncHTMLFromTextView?()
    }

    func toggleBulletList() { toggleLinePrefixes(numbered: false) }
    func toggleNumberedList() { toggleLinePrefixes(numbered: true) }

    func insertText(_ text: String) {
        guard let textView, let storage = storage(of: textView) else { return }
        let range = selectedRange(of: textView)
        let attributes = typingAttributes(of: textView, at: range)
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0), on: textView)
        syncHTMLFromTextView?()
    }

    private func toggleFontTrait(bold: Bool) {
        guard let textView, let storage = storage(of: textView) else { return }
        let range = selectedRange(of: textView)
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? PlatformFont) ?? PlatformFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(.font, value: Self.toggledFont(font, bold: bold), range: subrange)
        }
        storage.endEditing()
        syncHTMLFromTextView?()
    }

    private func toggleLinePrefixes(numbered: Bool) {
        guard let textView, let storage = storage(of: textView) else { return }
        let selection = selectedRange(of: textView)
        let fullText = storage.string as NSString
        let lineRange = fullText.lineRange(for: selection)
        let lines = fullText.substring(with: lineRange).components(separatedBy: "\n")

        let bulletPrefix = "• "
        let hasAnyPrefix = lines.allSatisfy { line in
            line.isEmpty || line.hasPrefix(bulletPrefix) || line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }

        var rebuilt: [String] = []
        for (index, line) in lines.enumerated() {
            var stripped = line
            if stripped.hasPrefix(bulletPrefix) {
                stripped.removeFirst(bulletPrefix.count)
            } else if let match = stripped.range(of: #"^\d+\. "#, options: .regularExpression) {
                stripped.removeSubrange(match)
            }
            if hasAnyPrefix || stripped.isEmpty {
                rebuilt.append(stripped)
            } else {
                rebuilt.append(numbered ? "\(index + 1). \(stripped)" : "\(bulletPrefix)\(stripped)")
            }
        }

        let replacement = rebuilt.joined(separator: "\n")
        storage.beginEditing()
        storage.replaceCharacters(in: lineRange, with: replacement)
        storage.endEditing()
        syncHTMLFromTextView?()
    }

    private static func toggledFont(_ font: PlatformFont, bold: Bool) -> PlatformFont {
        #if os(iOS)
        let trait: UIFontDescriptor.SymbolicTraits = bold ? .traitBold : .traitItalic
        var traits = font.fontDescriptor.symbolicTraits
        traits.formSymmetricDifference(trait)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #elseif os(macOS)
        let trait: NSFontDescriptor.SymbolicTraits = bold ? .bold : .italic
        var traits = font.fontDescriptor.symbolicTraits
        traits.formSymmetricDifference(trait)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }

    private func selectedRange(of textView: PlatformTextView) -> NSRange {
        #if os(iOS)
        return textView.selectedRange
        #elseif os(macOS)
        return textView.selectedRange()
        #endif
    }

    private func setSelectedRange(_ range: NSRange, on textView: PlatformTextView) {
        #if os(iOS)
        textView.selectedRange = range
        #elseif os(macOS)
        textView.setSelectedRange(range)
        #endif
    }

    private func typingAttributes(of textView: PlatformTextView, at range: NSRange) -> [NSAttributedString.Key: Any] {
        guard let storage = storage(of: textView), range.location > 0, range.location <= storage.length else {
            return textView.typingAttributes
        }
        return storage.attributes(at: max(0, range.location - 1), effectiveRange: nil)
    }

    private func storage(of textView: PlatformTextView) -> NSTextStorage? {
        textView.textStorage
    }
}

#if os(iOS)
struct StepRichTextEditorRepresentable: UIViewRepresentable {
    @Binding var html: String
    let controller: StepRichTextEditorController

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.accessibilityIdentifier = "stepDescriptionField"
        context.coordinator.apply(html: html, to: textView)
        controller.textView = textView
        controller.syncHTMLFromTextView = { [weak textView] in
            guard let textView else { return }
            context.coordinator.pushHTML(from: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.apply(html: html, to: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(html: $html)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var htmlBinding: Binding<String>
        var lastHTML = ""

        init(html: Binding<String>) {
            self.htmlBinding = html
        }

        func apply(html: String, to textView: UITextView) {
            lastHTML = html
            textView.attributedText = RichTextHTMLCodec.attributedString(from: html) ?? NSAttributedString(string: html)
        }

        func pushHTML(from textView: UITextView) {
            let newHTML = RichTextHTMLCodec.html(from: textView.attributedText)
            lastHTML = newHTML
            htmlBinding.wrappedValue = newHTML
        }

        func textViewDidChange(_ textView: UITextView) {
            pushHTML(from: textView)
        }
    }
}
#elseif os(macOS)
struct StepRichTextEditorRepresentable: NSViewRepresentable {
    @Binding var html: String
    let controller: StepRichTextEditorController

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = true
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.setAccessibilityIdentifier("stepDescriptionField")
        textView.isEditable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.apply(html: html, to: textView)
        controller.textView = textView
        controller.syncHTMLFromTextView = { [weak textView] in
            guard let textView else { return }
            context.coordinator.pushHTML(from: textView)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.lastHTML != html {
            context.coordinator.apply(html: html, to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(html: $html)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var htmlBinding: Binding<String>
        var lastHTML = ""

        init(html: Binding<String>) {
            self.htmlBinding = html
        }

        func apply(html: String, to textView: NSTextView) {
            lastHTML = html
            let attributed = RichTextHTMLCodec.attributedString(from: html) ?? NSAttributedString(string: html)
            textView.textStorage?.setAttributedString(attributed)
        }

        func pushHTML(from textView: NSTextView) {
            let newHTML = RichTextHTMLCodec.html(from: textView.attributedString())
            lastHTML = newHTML
            htmlBinding.wrappedValue = newHTML
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            pushHTML(from: textView)
        }
    }
}
#endif

#if os(macOS)
private extension NSFont {
    static func preferredFont(forTextStyle style: NSFont.TextStyle) -> NSFont {
        NSFont.preferredFont(forTextStyle: style, options: [:])
    }
}
#endif

struct StepRichTextEditor: View {
    @Binding var html: String
    let stepReagents: [(stepReagent: CachedStepReagent, reagent: CachedReagent)]
    let onAttachNewReagent: (() -> Void)?

    @State private var controller = StepRichTextEditorController()
    @State private var isShowingInsertReagentPicker = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Button {
                        controller.toggleBold()
                    } label: {
                        Image(systemName: "bold")
                    }
                    .accessibilityIdentifier("stepEditorBoldButton")
                    .help("Bold")

                    Button {
                        controller.toggleItalic()
                    } label: {
                        Image(systemName: "italic")
                    }
                    .accessibilityIdentifier("stepEditorItalicButton")
                    .help("Italic")

                    Button {
                        controller.toggleUnderline()
                    } label: {
                        Image(systemName: "underline")
                    }
                    .accessibilityIdentifier("stepEditorUnderlineButton")
                    .help("Underline")

                    Button {
                        controller.toggleBulletList()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityIdentifier("stepEditorBulletListButton")
                    .help("Bullet List")

                    Button {
                        controller.toggleNumberedList()
                    } label: {
                        Image(systemName: "list.number")
                    }
                    .accessibilityIdentifier("stepEditorNumberedListButton")
                    .help("Numbered List")
                }
                .buttonStyle(.bordered)

                StepRichTextEditorRepresentable(html: $html, controller: controller)
                    .frame(minHeight: 140)
            }

            Button {
                isShowingInsertReagentPicker = true
            } label: {
                Label("Insert Reagent", systemImage: "eyedropper")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("insertReagentTokenButton")
            .help("Insert Reagent Token")
        }
        .popover(isPresented: $isShowingInsertReagentPicker) {
            InsertReagentTokenView(
                stepReagents: stepReagents,
                onInsert: { token in
                    controller.insertText(token)
                    isShowingInsertReagentPicker = false
                },
                onAttachNewReagent: onAttachNewReagent.map { attach in
                    { isShowingInsertReagentPicker = false; attach() }
                }
            )
        }
    }
}
