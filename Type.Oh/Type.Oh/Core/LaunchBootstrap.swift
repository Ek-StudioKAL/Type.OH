import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Observation

/// Drives the launch splash: runs a small sequence of warm-up tasks, reports
/// progress, and signals completion. Each step writes the human-readable
/// `step` label and bumps `progress` so the splash bar advances visibly.
///
/// Steps are intentionally read-only — none of them *requests* permissions
/// (that's onboarding's job). The bootstrap just observes current state so
/// the first hotkey press lands on warmed caches instead of cold modules.
@Observable
@MainActor
final class LaunchBootstrap {
    private(set) var progress: Double = 0.0
    private(set) var step: String = "Starting…"
    private(set) var isComplete: Bool = false

    private weak var settings: SettingsStore?
    private weak var whisperService: WhisperService?

    init(settings: SettingsStore, whisperService: WhisperService) {
        self.settings = settings
        self.whisperService = whisperService
    }

    /// Run all warm-up steps in order. Bounded by a soft 8 s budget — if any
    /// step hangs (e.g. WhisperKit network stall) the splash hides anyway so
    /// the app remains usable.
    func run() async {
        let deadline = Date().addingTimeInterval(8)
        defer { finish() }

        await runStep("Checking permissions", weight: 0.10) {
            // Pure observation — `AXIsProcessTrusted()` and
            // `AVCaptureDevice.authorizationStatus(for:)` are sync and cheap.
            _ = AXIsProcessTrusted()
            _ = AVCaptureDevice.authorizationStatus(for: .audio)
        }

        await runStep("Warming Keychain", weight: 0.15) {
            guard let provider = self.settings?.activeProvider else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    KeychainStore.prefetch(provider)
                    continuation.resume()
                }
            }
        }

        guard Date() < deadline else { return }

        await runStep("Loading Whisper model", weight: 0.75) {
            guard
                let settings = self.settings,
                settings.whisperKeepLoaded,
                let folder = ModelManager.shared.modelFolderURL(for: settings.whisperModel),
                ModelManager.shared.isDownloaded(settings.whisperModel),
                let service = self.whisperService
            else { return }
            try? await service.loadModel(name: settings.whisperModel, at: folder)
        }
    }

    private func runStep(_ name: String, weight: Double, _ body: () async -> Void) async {
        step = name
        await body()
        progress = min(1.0, progress + weight)
    }

    private func finish() {
        step = "Ready"
        progress = 1.0
        isComplete = true
    }
}
