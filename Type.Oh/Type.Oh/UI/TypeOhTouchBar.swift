import AppKit

/// Touch Bar for LazyPad and ReType (MacBook Pro with a Touch Bar).
///
/// The bar is stateless: each button posts `notification` with its item id
/// as the object, and the SwiftUI view that owns the window runs the action
/// (`ScratchpadView` / `AIEditorPanel` `.onReceive`). The window keeps this
/// object alive — `NSTouchBar.delegate` is weak.
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

    private static let stylesIdentifier = NSTouchBarItem.Identifier("com.typeoh.touchbar.styles")

    private let notification: Notification.Name
    private let items: [Item]
    /// Shown behind a "Styles" button (LazyPad only); empty hides the button.
    private let styleItems: [Item]

    init(notification: Notification.Name, items: [Item], styleItems: [Item] = []) {
        self.notification = notification
        self.items = items
        self.styleItems = styleItems
    }

    /// LazyPad: the toolbar's rewrite actions plus every style preset.
    static func lazyPad(customPresets: [CustomStylePreset]) -> TypeOhTouchBar {
        let styles = StylePresets.all.map { Item(id: "style:\($0.id)", title: $0.label, icon: styleIcon(for: $0)) }
            + customPresets.map { Item(id: "style:\($0.id)", title: "\($0.emoji) \($0.label)") }
        return TypeOhTouchBar(
            notification: lazyPadAction,
            items: [
                Item(id: "dictate", title: "Dictate", icon: .dictate),
                Item(id: "improve", title: "Improve", icon: .improve),
                Item(id: "fix", title: "Fix", icon: .fix),
                Item(id: "concise", title: "Concise", icon: .concise),
                Item(id: "translate", title: "Translate", icon: .translate),
            ],
            styleItems: styles
        )
    }

    /// ReType: each button runs that action right away; Insert applies the result.
    static func reType() -> TypeOhTouchBar {
        TypeOhTouchBar(
            notification: reTypeAction,
            items: [
                Item(id: "fix", title: "Fix", icon: .fix),
                Item(id: "improve", title: "Improve", icon: .improve),
                Item(id: "translate", title: "Translate", icon: .translate),
                Item(id: "insert", title: "Insert", isPrimary: true),
            ]
        )
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = items.map(identifier(for:))
            + (styleItems.isEmpty ? [] : [.fixedSpaceSmall, Self.stylesIdentifier])
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == Self.stylesIdentifier {
            let popover = NSPopoverTouchBarItem(identifier: identifier)
            popover.collapsedRepresentationLabel = "Styles"
            popover.collapsedRepresentationImage = AppIcon.style.nsImage(size: 18)
            let styles = NSTouchBar()
            styles.delegate = self
            styles.defaultItemIdentifiers = styleItems.map(self.identifier(for:))
            popover.popoverTouchBar = styles
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
        if item.isPrimary {
            button.bezelColor = .typeOhAccent
        }
        let touchBarItem = NSCustomTouchBarItem(identifier: identifier)
        touchBarItem.view = button
        touchBarItem.customizationLabel = item.title
        return touchBarItem
    }

    @objc private func tap(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        NotificationCenter.default.post(name: notification, object: id)
    }

    private func identifier(for item: Item) -> NSTouchBarItem.Identifier {
        NSTouchBarItem.Identifier("com.typeoh.touchbar.\(item.id)")
    }
}
