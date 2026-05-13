import AppKit
import SwiftUI

/// Launch splash. Shown by `AppDelegate.applicationDidFinishLaunching` once
/// onboarding is past, hides itself when the attached `LaunchBootstrap`
/// reports `isComplete`.
///
/// SF Rounded is used throughout — the typographic mark the user picked for
/// this surface. Reference layout: `~/Type.OH/Splash_screen-ref/referance.png`.
/// The hero logo currently uses the app icon; swap to the SVG assets in
/// `Splash_screen-ref/` once they're added to Assets.xcassets.
struct LaunchSplash: View {
    @Bindable var bootstrap: LaunchBootstrap
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            logo

            VStack(spacing: 4) {
                Text("Type.OH")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("Voice + AI for everywhere you type")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: bootstrap.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 260)

                Text(bootstrap.step)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .lineLimit(1)
            }
        }
        .padding(36)
        .frame(width: 360, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onChange(of: bootstrap.isComplete) { _, done in
            guard done else { return }
            // Brief beat at 100% so the bar's completion is visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss()
            }
        }
    }

    private var logo: some View {
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "waveform")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 96, height: 96)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}
