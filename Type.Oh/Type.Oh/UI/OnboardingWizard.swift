import AppKit
import ApplicationServices
import AVFoundation
import FoundationModels
import SwiftUI

struct OnboardingWizard: View {
    @Environment(SettingsStore.self) private var settings

    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var manager = ModelManager.shared

    enum Step: Int, CaseIterable {
        case welcome
        case appleIntelligence
        case permissions
        case model
        case provider
        case summary

        var title: String {
            switch self {
            case .welcome:           "Welcome to Type.OH"
            case .appleIntelligence: "Apple Intelligence"
            case .permissions:       "Permissions"
            case .model:             "Voice Model"
            case .provider:          "AI Provider"
            case .summary:           "All Set"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.title2.weight(.semibold))
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            .padding(20)

            Divider()

            // Step content
            ScrollView {
                Group {
                    switch step {
                    case .welcome:           WelcomeStep()
                    case .appleIntelligence: AppleIntelligenceStep()
                    case .permissions:       PermissionsStep()
                    case .model:             ModelStep(manager: $manager)
                    case .provider:          ProviderStep()
                    case .summary:           SummaryStep(manager: manager)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 320)

            Divider()

            // Footer
            HStack {
                if step != .welcome {
                    Button("Back") { goBack() }
                }
                Spacer()
                if step == .summary {
                    Button("Finish") { finish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                } else {
                    Button(step == .welcome ? "Get Started" : "Next") { goNext() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                    Button("Skip") { finish() }
                        .help("Skip onboarding — you can configure everything later in Settings")
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
    }

    private var progress: Double {
        let total = Double(Step.allCases.count - 1)
        return Double(step.rawValue) / total
    }

    private func goNext() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func goBack() {
        if let prev = Step(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        settings.save()
        onFinish()
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type.OH gives you two superpowers, anywhere on your Mac:")
                .font(.body)

            featureRow(
                icon: "mic.fill",
                title: "⌃F13 — Voice to text",
                detail: "Hold the hotkey, speak, release. Transcribed locally and pasted at your cursor."
            )
            featureRow(
                icon: "wand.and.sparkles",
                title: "⌥F13 — AI editor",
                detail: "Select text in any app, press the hotkey, fix / restyle / translate, then apply."
            )

            Text("This wizard takes about a minute.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Step 2: Apple Intelligence

private struct AppleIntelligenceStep: View {
    @State private var status: String = ""
    @State private var available: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type.OH's default AI provider runs entirely on-device using Apple Intelligence.")

            HStack(spacing: 8) {
                Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(available ? .green : .orange)
                Text(status)
                    .font(.body.weight(.medium))
            }
            .padding(.vertical, 4)

            if !available {
                Text("Apple Intelligence requires macOS 26 on Apple Silicon and must be enabled in System Settings → Apple Intelligence & Siri.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Apple Intelligence Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.appleintelligence") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Text("You can still skip this and pick a cloud provider (Anthropic / OpenAI / Google) on the next steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                Text("You're ready to use the on-device model. No cloud round-trips, no API key required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability {
            available = true
            status = "Apple Intelligence is available"
        } else {
            available = false
            status = "Not available — \(String(describing: availability))"
        }
    }
}

// MARK: - Step 3: Permissions

private struct PermissionsStep: View {
    @State private var axTrusted: Bool = AXIsProcessTrusted()
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var refreshTimer: Timer?
    // Track whether user already opened AX settings so we can show the relaunch button.
    @State private var openedAXSettings: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Type.OH needs two permissions to capture text and audio.")

            // Accessibility row
            axRow()

            // Microphone row
            permissionRow(
                title: "Microphone",
                detail: "Required for the voice-to-text hotkey.",
                granted: micStatus == .authorized,
                openButton: micStatus == .notDetermined ? "Request Microphone Access" : "Open Microphone Settings",
                action: requestMicAccess
            )
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    @ViewBuilder
    private func axRow() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: axTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(axTrusted ? .green : .red)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Accessibility").font(.body.weight(.medium))
                Text("Required to read selected text from other apps and to paste results back.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !axTrusted {
                    HStack(spacing: 8) {
                        Button("Open Accessibility Settings") { openAccessibility() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        if openedAXSettings {
                            Button("Relaunch Type.OH") { relaunch() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                    if openedAXSettings {
                        Text("After toggling the switch in System Settings, relaunch to apply.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, openButton: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button(openButton) { action() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func openAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        openedAXSettings = true
    }

    private func relaunch() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6 && open '\(bundlePath)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func requestMicAccess() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                axTrusted = AXIsProcessTrusted()
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Step 4: Whisper model download

private struct ModelStep: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var manager: ModelManager

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a Whisper model for voice transcription. Models run locally on the Apple Neural Engine.")
                .fixedSize(horizontal: false, vertical: true)

            Text("`base` is recommended for most users — fast and accurate.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(manager.catalogue) { m in
                modelRow(m)
            }

            if let err = manager.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Text("You can change or download additional models later in Settings → Models.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func modelRow(_ m: WhisperModelInfo) -> some View {
        @Bindable var settings = settings
        let downloaded = manager.isDownloaded(m.id)
        let downloading = manager.downloadingModelID == m.id
        let isActive = settings.whisperModel == m.id

        HStack(spacing: 10) {
            Button {
                settings.whisperModel = m.id
                settings.save()
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(m.displayName).font(.body.weight(isActive ? .semibold : .regular))
                Text(m.sizeDescription).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if downloading {
                HStack(spacing: 6) {
                    ProgressView(value: manager.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                    Text("\(Int(manager.downloadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if downloaded {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Download") {
                    Task { try? await manager.download(m.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isDownloading)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step 5: Provider / API key

private struct ProviderStep: View {
    @Environment(SettingsStore.self) private var settings
    @State private var storedKeys: [ProviderID: String] = [:]
    @State private var draftKeys:  [ProviderID: String] = [:]

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 14) {
            Text("The default Apple (On-Device) provider needs no key. To use a cloud model, paste an API key — Type.OH stores it in your macOS Keychain.")
                .fixedSize(horizontal: false, vertical: true)

            Picker("Active provider", selection: $settings.activeProvider) {
                ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .onChange(of: settings.activeProvider) { settings.save() }

            ForEach(ProviderID.allCases.filter(\.requiresAPIKey), id: \.self) { p in
                providerRow(p)
            }

            Text("You can add or change keys later in Settings → Providers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .onAppear { loadKeys() }
    }

    @ViewBuilder
    private func providerRow(_ p: ProviderID) -> some View {
        let stored = storedKeys[p]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(p.displayName).font(.body.weight(.medium))
                Spacer()
                if stored != nil {
                    Text("••••" + String(stored!.suffix(4)))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                SecureField("Paste API key…", text: Binding(
                    get: { draftKeys[p] ?? "" },
                    set: { draftKeys[p] = $0 }
                ))
                Button("Save") {
                    let key = (draftKeys[p] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return }
                    if KeychainStore.save(key: key, for: p) {
                        storedKeys[p] = key
                        draftKeys[p] = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled((draftKeys[p] ?? "").isEmpty)
                if stored != nil {
                    Button("Clear") {
                        KeychainStore.delete(for: p)
                        storedKeys[p] = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadKeys() {
        for p in ProviderID.allCases where p.requiresAPIKey {
            storedKeys[p] = KeychainStore.load(for: p)
        }
    }
}

// MARK: - Step 6: Summary

private struct SummaryStep: View {
    @Environment(SettingsStore.self) private var settings
    let manager: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set up. Here's a quick recap:")
                .font(.body)

            summaryRow(label: "Voice model", value: voiceModelLabel)
            summaryRow(label: "AI provider", value: settings.activeProvider.displayName)
            summaryRow(label: "Voice hotkey", value: "⌃F13")
            summaryRow(label: "Editor hotkey", value: "⌥F13")

            Divider().padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Next steps").font(.body.weight(.medium))
                Text("• Press ⌃F13 anywhere to dictate.")
                Text("• Select text and press ⌥F13 to fix, restyle, or translate it.")
                Text("• Type.OH lives in your menu bar — click the waveform icon for Settings.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var voiceModelLabel: String {
        let id = settings.whisperModel
        let display = manager.catalogue.first(where: { $0.id == id })?.displayName ?? id
        let downloaded = manager.isDownloaded(id)
        return downloaded ? "\(display) (ready)" : "\(display) (not downloaded)"
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.weight(.medium))
        }
    }
}
