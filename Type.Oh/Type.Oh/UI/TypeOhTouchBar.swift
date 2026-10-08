import AppKit
import Combine

/// Touch Bar for LazyPad and ReType (MacBook Pro with a Touch Bar).
///
/// The bar is stateless: each button posts `notification` with its item id
/// as the object, and the SwiftUI view that owns the window runs the action
/// (`ScratchpadView` / `AIEditorPanel` `.onReceive`). The window keeps this
/// object alive — `NSTouchBar.delegate` is weak.
///
/// LazyPad's bar is compact, like TextEdit's B / I / U: the actions and the
/// style presets are two icon-only segmented controls, so the actions still
/// fit next to the typing suggestions in a text field (`TypeOhTextView`).
/// Separate buttons can't: Touch Bar buttons are at least 72 pt wide, and the
/// expanded suggestions take 445 of the ~685 pt app region. The styles have
/// low priority, so they show only when the suggestions are folded.
///
/// ReType's bar has room for labels and no suggestions:
/// Fix · Improve · Style (a popover of the presets) · Translate (en) … Insert.
/// Translate shows the target language (`settings.targetLanguage`, which
/// both windows' language pickers write) and follows it as it changes; in
/// LazyPad's icon strip the code replaces the icon.
///
/// Global actions (Dictate / ReType / LazyPad from any app) use the Quick
/// Actions in `touchbar/`, since an app's own bar only shows while it's active.
@MainActor
final class TypeOhTouchBar: NSObject, NSTouchBarDelegate {
    struct Item {
        let id: String
        let title: String
        var icon: AppIcon?
        var isPrimary = false
    }

    static let lazyPadAction = Notification.Name("typeoh.lazypad.touchBarAction")
    static let reTypeAction = Notification.Name("typeoh.retype.touchBarAction")

    private static let actionsIdentifier = NSTouchBarItem.Identifier("com.typeoh.touchbar.actions")
    private static let stylesIdentifier = NSTouchBarItem.Identifier("com.typeoh.touchbar.styles")
    private static let stylesPopoverIdentifier = NSTouchBarItem.Identifier("com.typeoh.touchbar.stylesPopover")

    enum Layout {
        /// LazyPad: icon-only actions and styles, next to the typing suggestions.
        case compact
        /// ReType: labelled buttons, styles in a popover, Insert at the far right.
        case reType
    }

    private let notification: Notification.Name
    private let layout: Layout
    private let items: [Item]
    private let styleItems: [Item]
    /// ReType's Style popover, closed once a style is picked.
    private weak var stylesPopover: NSPopoverTouchBarItem?
    /// Translate controls showing the target language (one per bar built).
    private var translateButtons: [Weak<NSButton>] = []
    private var translateSegments: [Weak<NSSegmentedControl>] = []
    private var languageCode: String
    private var languageObserver: AnyCancellable?

    init(notification: Notification.Name, layout: Layout, items: [Item], styleItems: [Item], settings: SettingsStore) {
        self.notification = notification
        self.layout = layout
        self.items = items
        self.styleItems = styleItems
        self.languageCode = Self.shortCode(settings.targetLanguage)
        super.init()
        languageObserver = settings.$targetLanguage
            .map(Self.shortCode)
            .removeDuplicates()
            .sink { [weak self] code in
                MainActor.assumeIsolated { self?.showLanguage(code) }
            }
    }

    /// "en", "ru", "pt" … from a language identifier like "pt-BR".
    private static func shortCode(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
    }

    private func showLanguage(_ code: String) {
        languageCode = code
        for button in translateButtons.compactMap(\.value) {
            button.title = "Translate (\(code))"
        }
        for control in translateSegments.compactMap(\.value) {
            if let index = items.firstIndex(where: { $0.id == "translate" }) {
                control.setLabel(code, forSegment: index)
            }
        }
    }

    /// Custom presets as style items: emoji only in LazyPad's icon strip,
    /// emoji and name in ReType's popover.
    private static func styleItems(customPresets: [CustomStylePreset], compact: Bool) -> [Item] {
        StylePresets.all.map { Item(id: "style:\($0.id)", title: $0.label, icon: styleIcon(for: $0)) }
            + customPresets.map { Item(id: "style:\($0.id)", title: compact ? $0.emoji : "\($0.emoji) \($0.label)") }
    }

    /// Whether a text view adds Apple's typing suggestions to this bar.
    var showsSuggestions: Bool { layout == .compact }

    /// LazyPad: the toolbar's rewrite actions plus every style preset.
    static func lazyPad(settings: SettingsStore) -> TypeOhTouchBar {
        TypeOhTouchBar(
            notification: lazyPadAction,
            layout: .compact,
            items: [
                Item(id: "dictate", title: "Dictate", icon: .dictate),
                Item(id: "improve", title: "Improve", icon: .improve),
                Item(id: "fix", title: "Fix", icon: .fix),
                Item(id: "concise", title: "Concise", icon: .concise),
                Item(id: "translate", title: "Translate"),
            ],
            styleItems: styleItems(customPresets: settings.customStylePresets, compact: true),
            settings: settings
        )
    }

    /// ReType: each button runs that action right away (a style from the
    /// Style popover runs Style with it); Insert applies the result.
    static func reType(settings: SettingsStore) -> TypeOhTouchBar {
        TypeOhTouchBar(
            notification: reTypeAction,
            layout: .reType,
            items: [
                Item(id: "fix", title: "Fix", icon: .fix),
                Item(id: "improve", title: "Improve", icon: .improve),
                Item(id: "translate", title: "Translate", icon: .translate),
                Item(id: "insert", title: "Insert", isPrimary: true),
            ],
            styleItems: styleItems(customPresets: settings.customStylePresets, compact: false),
            settings: settings
        )
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = itemIdentifiers
        return bar
    }

    /// The bar's items, for a text view that adds the typing suggestions.
    var itemIdentifiers: [NSTouchBarItem.Identifier] {
        switch layout {
        case .compact:
            return [Self.actionsIdentifier, .fixedSpaceSmall, Self.stylesIdentifier]
        case .reType:
            let ids = items.map(identifier(for:))
            return [ids[0], ids[1], Self.stylesPopoverIdentifier, .fixedSpaceLarge, ids[2], .flexibleSpace, ids[3]]
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == Self.actionsIdentifier {
            return segmentedItem(identifier, items: items)
        }
        if identifier == Self.stylesIdentifier {
            let item = segmentedItem(identifier, items: styleItems)
            item.visibilityPriority = .low
            return item
        }
        if identifier == Self.stylesPopoverIdentifier {
            let popover = NSPopoverTouchBarItem(identifier: identifier)
            popover.collapsedRepresentationLabel = "Style"
            popover.collapsedRepresentationImage = AppIcon.style.nsImage(size: 18)
            popover.customizationLabel = "Style"
            let styles = NSTouchBar()
            styles.delegate = self
            styles.defaultItemIdentifiers = styleItems.map(self.identifier(for:))
            popover.popoverTouchBar = styles
            stylesPopover = popover
            return popover
        }

        guard let item = (items + styleItems).first(where: { self.identifier(for: $0) == identifier }) else {
            return nil
        }
        let button: NSButton
        if let icon = item.icon {
            button = NSButton(title: item.title, image: icon.nsImage(size: 18), target: self, action: #selector(tap(_:)))
            button.imagePosition = .imageLeading
        } else {
            button = NSButton(title: item.title, target: self, action: #selector(tap(_:)))
        }
        button.identifier = NSUserInterfaceItemIdentifier(item.id)
        if item.id == "translate" {
            button.title = "Translate (\(languageCode))"
            translateButtons.append(Weak(button))
        }
        if item.isPrimary {
            button.bezelColor = .typeOhAccent
        }
        let touchBarItem = NSCustomTouchBarItem(identifier: identifier)
        touchBarItem.view = button
        touchBarItem.customizationLabel = item.title
        return touchBarItem
    }

    /// Icon-only momentary segments; each one posts its item's id.
    private func segmentedItem(_ identifier: NSTouchBarItem.Identifier, items: [Item]) -> NSCustomTouchBarItem {
        let control = NSSegmentedControl(labels: items.map { _ in "" }, trackingMode: .momentary,
                                         target: self, action: #selector(tapSegment(_:)))
        for (index, item) in items.enumerated() {
            if let icon = item.icon {
                control.setImage(icon.nsImage(size: 24), forSegment: index)
                control.setLabel("", forSegment: index)
            } else {
                control.setLabel(item.id == "translate" ? languageCode : item.title, forSegment: index)
            }
            control.setWidth(44, forSegment: index)
        }
        control.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        if items.contains(where: { $0.id == "translate" }) {
            translateSegments.append(Weak(control))
        }
        let touchBarItem = NSCustomTouchBarItem(identifier: identifier)
        touchBarItem.view = control
        touchBarItem.customizationLabel = identifier == Self.stylesIdentifier ? "Styles" : "Actions"
        return touchBarItem
    }

    @objc private func tapSegment(_ sender: NSSegmentedControl) {
        let group = sender.identifier?.rawValue == Self.stylesIdentifier.rawValue ? styleItems : items
        guard group.indices.contains(sender.selectedSegment) else { return }
        NotificationCenter.default.post(name: notification, object: group[sender.selectedSegment].id)
    }

    @objc private func tap(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        // A style picked from the popover: close it again.
        if id.hasPrefix("style:") {
            stylesPopover?.dismissPopover(nil)
        }
        NotificationCenter.default.post(name: notification, object: id)
    }

    private func identifier(for item: Item) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("com.typeoh.touchbar.\(item.id)")
    }
}

private struct Weak<Object: AnyObject> {
    weak var value: Object?
    init(_ value: Object) { self.value = value }
}
