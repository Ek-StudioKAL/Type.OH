import AppKit
import SwiftUI

@MainActor
final class NativeTextViewController {
    fileprivate weak var textView: NSTextView?
    fileprivate var onProgrammaticEdit: (() -> Void)?

    var currentText: String? {
        textView?.string
    }

    var hasSelection: Bool {
        guard let textView else { return false }
        let range = textView.selectedRange()
        return range.location != NSNotFound && range.length > 0
    }

    func selectedRange() -> NSRange? {
        guard let textView else { return nil }
        let range = textView.selectedRange()
        guard range.location != NSNotFound else { return nil }
        return range
    }

    func replaceCharacters(in range: NSRange, with replacement: String) {
        guard let textView, let textStorage = textView.textStorage else { return }
        guard NSMaxRange(range) <= textStorage.length else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }

        textStorage.beginEditing()
        textStorage.replaceCharacters(
            in: range,
            with: NSAttributedString(string: replacement, attributes: replacementAttributes(for: textView, at: range.location))
        )
        textStorage.endEditing()
        textView.didChangeText()
        textView.invalidateRenderedText()

        let insertionPoint = range.location + (replacement as NSString).length
        textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
        textView.scrollRangeToVisible(NSRange(location: insertionPoint, length: 0))
        onProgrammaticEdit?()
    }

    func replaceAllText(with replacement: String) {
        guard let textView else { return }
        replaceCharacters(in: NSRange(location: 0, length: textView.string.utf16.count), with: replacement)
    }

    private func replacementAttributes(for textView: NSTextView, at location: Int) -> [NSAttributedString.Key: Any] {
        var attributes = textView.typingAttributes
        if location > 0,
           location <= textView.textStorage?.length ?? 0,
           let inherited = textView.textStorage?.attributes(at: location - 1, effectiveRange: nil) {
            attributes.merge(inherited) { current, _ in current }
        }
        attributes[.font] = attributes[.font] ?? textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        attributes[.foregroundColor] = attributes[.foregroundColor] ?? textView.textColor ?? NSColor.labelColor
        return attributes
    }

    /// Replace the entire contents with no undo registration. Used by `Clear`.
    func resetText(to replacement: String) {
        guard let textView, let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.replaceCharacters(
            in: fullRange,
            with: NSAttributedString(string: replacement, attributes: replacementAttributes(for: textView, at: 0))
        )
        textStorage.endEditing()
        textView.undoManager?.removeAllActions()
        textView.didChangeText()
        textView.invalidateRenderedText()
        textView.setSelectedRange(NSRange(location: (replacement as NSString).length, length: 0))
        onProgrammaticEdit?()
    }
}

struct NativeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let spellingAssistanceEnabled: Bool
    let grammarAssistanceEnabled: Bool
    let textReplacementEnabled: Bool
    let controller: NativeTextViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange, controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = .textBackgroundColor

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        applyAssistance(to: textView)
        textView.isAutomaticDataDetectionEnabled = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.alignment = .natural
        textView.baseWritingDirection = .natural
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.lastSyncedText = text

        scrollView.documentView = textView
        controller.textView = textView
        context.coordinator.textView = textView

        // Programmatic edits (AI replace, Clear) re-sync the coordinator's cache so the
        // next updateNSView pass doesn't see a false "binding drifted" condition.
        controller.onProgrammaticEdit = { [weak coordinator = context.coordinator] in
            guard let coordinator, let tv = coordinator.textView else { return }
            coordinator.lastSyncedText = tv.string
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // CRITICAL: never assign `textView.string = text` from here.
        //
        // SwiftUI re-renders are async. During fast typing the `text` binding lags
        // behind `textView.string` (the user has typed chars SwiftUI hasn't applied
        // yet). Re-assigning `string` would drop those keystrokes, blow away the
        // undo stack, and interrupt IME composition.
        //
        // We only react when the *binding* changed independently of the text view —
        // e.g. SwiftUI parent set text to something new (".clear()" path uses the
        // controller, not the binding, to avoid this entirely). For safety we
        // tolerate an out-of-band binding write only when the new value also
        // differs from the last value we synced *out* of the text view.
        if text != context.coordinator.lastSyncedText && text != textView.string {
            let preservedSelection = textView.selectedRange()
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: fullRange, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: fullRange, with: text)
                textView.didChangeText()
                textView.invalidateRenderedText()
            }
            if preservedSelection.location != NSNotFound,
               NSMaxRange(preservedSelection) <= (textView.string as NSString).length {
                textView.setSelectedRange(preservedSelection)
            }
            context.coordinator.lastSyncedText = textView.string
        }

        if selectedRange.location != NSNotFound,
           selectedRange != textView.selectedRange(),
           NSMaxRange(selectedRange) <= (textView.string as NSString).length {
            textView.setSelectedRange(selectedRange)
        }

        applyAssistance(to: textView)
        controller.textView = textView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.controller.onProgrammaticEdit = nil
        coordinator.controller.textView = nil
    }

    private func applyAssistance(to textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = spellingAssistanceEnabled
        textView.isGrammarCheckingEnabled = grammarAssistanceEnabled
        textView.isAutomaticSpellingCorrectionEnabled = spellingAssistanceEnabled
        textView.isAutomaticTextReplacementEnabled = textReplacementEnabled
        textView.isAutomaticQuoteSubstitutionEnabled = grammarAssistanceEnabled
        textView.isAutomaticDashSubstitutionEnabled = grammarAssistanceEnabled
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        let controller: NativeTextViewController
        weak var textView: NSTextView?
        /// The last text value we pushed *out* of the text view. Used by
        /// `updateNSView` to distinguish "user is typing" (textView ahead of binding)
        /// from "parent reassigned the binding" (binding ahead of textView).
        var lastSyncedText: String = ""

        init(text: Binding<String>, selectedRange: Binding<NSRange>, controller: NativeTextViewController) {
            _text = text
            _selectedRange = selectedRange
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let newValue = textView.string
            lastSyncedText = newValue
            if text != newValue { text = newValue }
            textView.invalidateRenderedText()
            let range = textView.selectedRange()
            if selectedRange != range { selectedRange = range }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            Task { @MainActor [weak self] in
                guard let self, self.textView != nil else { return }
                if self.selectedRange != range { self.selectedRange = range }
            }
        }
    }
}

private extension NSTextView {
    @MainActor
    func invalidateRenderedText() {
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
            layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: string.utf16.count))
        }

        invalidateIntrinsicContentSize()
        needsDisplay = true
        superview?.needsDisplay = true

        guard let scrollView = enclosingScrollView else { return }
        scrollView.contentView.needsDisplay = true
        scrollView.documentView?.needsDisplay = true
        scrollView.needsDisplay = true
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
