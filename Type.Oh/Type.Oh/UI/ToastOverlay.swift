import AppKit
import SwiftUI

@MainActor
final class ToastOverlay {
    static let shared = ToastOverlay()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    enum Kind {
        /// Something happened that the user should know about ("opened in LazyPad").
        case info
        /// The action didn't run; the user can fix it (missing permission).
        case warning
        /// The action failed.
        case error

        fileprivate var icon: AppIcon {
            switch self {
            case .info: .statusDot
            case .warning: .warning
            case .error: .needsAttention
            }
        }

        fileprivate var tint: Color {
            switch self {
            case .info: .white.opacity(0.75)
            case .warning: .yellow
            case .error: .red
            }
        }

        /// Errors stay up longer so they can be read.
        fileprivate var duration: Duration {
            switch self {
            case .info: .seconds(3.5)
            case .warning: .seconds(5)
            case .error: .seconds(6)
            }
        }
    }

    func show(_ message: String, kind: Kind) {
        dismissTask?.cancel()
        panel?.close()

        let hc = NSHostingController(rootView: ToastView(message: message, kind: kind).typeOhAccent())
        // Sized once below. Letting the controller track its preferred size
        // makes a message that wraps to two lines recurse in Auto Layout
        // until the main thread's stack overflows.
        hc.sizingOptions = []

        let p = NSPanel(
            contentRect: .zero,
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.isFloatingPanel  = true
        p.level            = .statusBar
        p.backgroundColor  = .clear
        p.isOpaque         = false
        p.hasShadow        = true
        p.contentViewController = hc
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let size = hc.view.fittingSize
            p.setContentSize(size)
            p.setFrameOrigin(CGPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.maxY - size.height - 24
            ))
        }

        p.orderFront(nil)
        panel = p

        // The panel never takes focus, so VoiceOver wouldn't read it otherwise.
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )

        dismissTask = Task {
            try? await Task.sleep(for: kind.duration)
            guard !Task.isCancelled else { return }
            panel?.close()
            panel = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        panel?.close()
        panel = nil
    }
}

@MainActor private struct ToastView: View {
    let message: String
    let kind: ToastOverlay.Kind

    /// Longer messages wrap at this width.
    private static let maxTextWidth: CGFloat = 360

    /// One line when the message fits, the wrap width otherwise. The width
    /// is explicit so the view's height never depends on the width the
    /// panel offers (see the sizing note in `ToastOverlay.show`).
    private var textWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let natural = (message as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(natural) + 2, Self.maxTextWidth)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(appIcon: kind.icon, size: 16)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(width: textWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .init(white: 0.12, alpha: 0.96)))
        )
        .padding(8)
        .fixedSize()
    }
}
