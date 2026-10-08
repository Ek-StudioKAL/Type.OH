import AppKit

// Type.OH Control Strip helper — bundled as
// Type.Oh.app/Contents/Helpers/TypeOhStrip.app and started by `ControlStrip`.
//
//     TypeOhStrip <action> <icon.pdf> <title> <parent pid>
//
// Puts one button in the Touch Bar's Control Strip; tapping it opens
// `typeoh://<action>` in the background, like the Quick Actions do. It runs
// in its own process because a process that adds a Control Strip button
// stops showing its own windows' Touch Bars (LazyPad / ReType).
//
// AppKit has no public API for this. It uses the private calls that Control
// Strip utilities (Pock, MTMR) rely on: `+[NSTouchBarItem addSystemTrayItem:]`
// and `DFRElementSetControlStripPresenceForIdentifier` from DFRFoundation,
// both looked up at runtime. Exits when the parent quits, and when the
// Control Strip restarts (it forgets the button), so the parent starts a
// fresh one.

let arguments = CommandLine.arguments
guard arguments.count == 5, let parentPID = pid_t(arguments[4]),
      let url = URL(string: "typeoh://\(arguments[1])") else {
    FileHandle.standardError.write("usage: TypeOhStrip <action> <icon.pdf> <title> <parent pid>\n".data(using: .utf8)!)
    exit(2)
}

typealias SetPresence = @convention(c) (CFString, DarwinBoolean) -> Void

final class StripButton: NSObject {
    private let url: URL
    private var item: NSCustomTouchBarItem?

    init(url: URL) {
        self.url = url
    }

    func show(iconPath: String, title: String) {
        let addSelector = NSSelectorFromString("addSystemTrayItem:")
        guard NSTouchBarItem.responds(to: addSelector),
              let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY),
              let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            NSLog("[Type.OH strip] Control Strip API unavailable")
            exit(1)
        }
        let setPresence = unsafeBitCast(symbol, to: SetPresence.self)

        let image = NSImage(contentsOfFile: iconPath) ?? NSImage()
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        let button = NSButton(image: image, target: self, action: #selector(tap))
        button.setAccessibilityLabel("Type.OH \(title)")
        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("com.typeoh.controlstrip"))
        item.view = button
        item.customizationLabel = "Type.OH \(title)"
        NSTouchBarItem.perform(addSelector, with: item)
        setPresence(item.identifier.rawValue as CFString, true)
        self.item = item
    }

    @objc private func tap() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let strip = StripButton(url: url)
// Add the button once the app is running.
DispatchQueue.main.async { strip.show(iconPath: arguments[2], title: arguments[3]) }

// Quit with the parent.
let parentExit = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .main)
parentExit.setEventHandler { exit(0) }
parentExit.resume()
if kill(parentPID, 0) != 0 { exit(0) }

// Quit when the Control Strip restarts; the parent starts a new helper.
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
) { note in
    let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    if launched?.bundleIdentifier == "com.apple.controlstrip" { exit(0) }
}

app.run()
