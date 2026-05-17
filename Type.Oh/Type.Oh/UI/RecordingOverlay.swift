import AppKit
import ApplicationServices
import AVFoundation
import Combine
import SwiftUI

/// State the HUD reads to label model + permission status. Computed once when
/// the panel is shown; the timer ticks locally inside the view.
struct DictationHUDState: Equatable {
    enum ModelStatus: Equatable {
        case loaded(displayName: String)
        case ready(displayName: String)   // downloaded but not yet loaded into RAM
        case missing
    }

    var modelStatus: ModelStatus
    var axTrusted: Bool
    var micAuthorized: Bool

    var isReady: Bool {
        if case .missing = modelStatus { return false }
        return axTrusted && micAuthorized
    }
}

enum DictationHUDPhase: Equatable {
    case recording
    case processing
}

/// Compact non-activating HUD shown during dictation. Replaces the old
/// "red-dot + timer" pill with a richer surface:
/// - Model-loaded indicator (matches Settings -> Whisper status).
/// - Permission badges (AX + mic) visible only if a permission is missing.
/// - Elapsed timer.
/// - Done button (commits: stop, transcribe, paste).
/// - Processing phase while Whisper is transcribing.
/// - Esc cancels while still recording.
///
/// The view is purely presentational; AppDelegate owns the recorder lifecycle.
/// User actions post `typeoh.voice.commit` / `typeoh.voice.cancel`; AppDelegate
/// routes those back into `handleVoiceKey` or `cancelVoiceRecording`.
struct RecordingOverlay: View {
    let state: DictationHUDState
    var phase: DictationHUDPhase = .recording

    @State private var elapsed = 0
    @State private var pulsing = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            phaseIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    modelBadge
                    if phase == .processing {
                        badge(icon: "waveform", tint: .accentColor, text: "Processing")
                    }
                    if !state.axTrusted { permissionBadge(label: "AX", systemImage: "exclamationmark.shield") }
                    if !state.micAuthorized { permissionBadge(label: "Mic", systemImage: "mic.slash") }
                }
            }

            Spacer(minLength: 8)

            if phase == .recording {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("typeoh.voice.commit"), object: nil)
                } label: {
                    Text("Done")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Stop and transcribe (Return)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: phase == .processing ? 300 : 260)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .onAppear { pulsing = true }
        .onReceive(clock) { _ in elapsed += 1 }
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        switch phase {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.35 : 0.85)
                .opacity(pulsing ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private var modelBadge: some View {
        switch state.modelStatus {
        case .loaded(let name):
            badge(icon: "checkmark.circle.fill", tint: .green, text: name)
        case .ready(let name):
            badge(icon: "circle.fill", tint: .teal, text: name)
        case .missing:
            badge(icon: "exclamationmark.circle.fill", tint: .orange, text: "No model")
        }
    }

    private func badge(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func permissionBadge(label: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.orange.opacity(0.18)))
    }

    private var primaryLabel: String {
        switch phase {
        case .recording:
            timeString
        case .processing:
            "Processing..."
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

#Preview {
    VStack(spacing: 12) {
        RecordingOverlay(state: DictationHUDState(
            modelStatus: .loaded(displayName: "base"),
            axTrusted: true,
            micAuthorized: true
        ))
        RecordingOverlay(
            state: DictationHUDState(
                modelStatus: .loaded(displayName: "base"),
                axTrusted: true,
                micAuthorized: true
            ),
            phase: .processing
        )
    }
    .padding()
}
