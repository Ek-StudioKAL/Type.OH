import AppKit
import SwiftUI

@MainActor
final class ToastOverlay {
    static let shared = ToastOverlay()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String) {
        dismissTask?.cancel()
        panel?.close()

        let hc = NSHostingController(rootView: ToastView(message: message))
        hc.sizingOptions = .preferredContentSize

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

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            panel?.close()
            panel = nil
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .init(white: 0.12, alpha: 0.96)))
        )
        .padding(8)
    }
}
