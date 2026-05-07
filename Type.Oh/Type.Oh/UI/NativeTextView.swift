import AppKit
import SwiftUI

@MainActor
final class NativeTextViewController {
    fileprivate weak var textView: NSTextView?

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
        textStorage.replaceCharacters(in: range, with: replacement)
        textStorage.endEditing()
        textView.didChangeText()

        let insertionPoint = range.location + (replacement as NSString).length
        textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
        textView.scrollRangeToVisible(NSRange(location: insertionPoint, length: 0))
    }

    func replaceAllText(with replacement: String) {
        guard let textView else { return }
        replaceCharacters(in: NSRange(location: 0, length: textView.string.utf16.count), with: replacement)
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
        scrollView.drawsBackground = false

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
        textView.isContinuousSpellCheckingEnabled = spellingAssistanceEnabled
        textView.isGrammarCheckingEnabled = grammarAssistanceEnabled
        textView.isAutomaticSpellingCorrectionEnabled = spellingAssistanceEnabled
        textView.isAutomaticTextReplacementEnabled = textReplacementEnabled
        textView.isAutomaticQuoteSubstitutionEnabled = grammarAssistanceEnabled
        textView.isAutomaticDashSubstitutionEnabled = grammarAssistanceEnabled
        textView.isAutomaticDataDetectionEnabled = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.alignment = .natural
        textView.baseWritingDirection = .natural
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        controller.textView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            let preservedSelection = textView.selectedRange()
            textView.string = text
            if preservedSelection.location != NSNotFound, NSMaxRange(preservedSelection) <= textView.string.utf16.count {
                textView.setSelectedRange(preservedSelection)
            }
        }

        if selectedRange.location != NSNotFound,
           selectedRange != textView.selectedRange(),
           NSMaxRange(selectedRange) <= textView.string.utf16.count {
            textView.setSelectedRange(selectedRange)
        }

        textView.isContinuousSpellCheckingEnabled = spellingAssistanceEnabled
        textView.isGrammarCheckingEnabled = grammarAssistanceEnabled
        textView.isAutomaticSpellingCorrectionEnabled = spellingAssistanceEnabled
        textView.isAutomaticTextReplacementEnabled = textReplacementEnabled
        textView.isAutomaticQuoteSubstitutionEnabled = grammarAssistanceEnabled
        textView.isAutomaticDashSubstitutionEnabled = grammarAssistanceEnabled

        controller.textView = textView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.controller.textView = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        let controller: NativeTextViewController
        weak var textView: NSTextView?

        init(text: Binding<String>, selectedRange: Binding<NSRange>, controller: NativeTextViewController) {
            _text = text
            _selectedRange = selectedRange
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            selectedRange = textView.selectedRange()
        }
    }
}
