import SwiftUI
import Translation

/// Bridges the imperative `TranslationDispatcher.translate(.nativeOS, ...)`
/// call into the SwiftUI-driven `TranslationSession` API.
///
/// The flow:
/// 1. `TranslationDispatcher` awaits `NativeTranslationCoordinator.shared.translate(...)`.
/// 2. The coordinator stores the pending config + text and parks a continuation.
/// 3. The mounted `NativeTranslationDriverView` (one per LazyPad / ReType panel)
///    observes the coordinator. Its `.translationTask(_:)` modifier fires when
///    `pendingConfiguration` becomes non-nil — Apple drives a `TranslationSession`,
///    optionally prompting the user to download the language pack.
/// 4. The driver calls `session.translate(_:)` and resolves the continuation.
@MainActor
@Observable
final class NativeTranslationCoordinator {
    static let shared = NativeTranslationCoordinator()

    /// Bumped on every new request so SwiftUI re-evaluates the
    /// `.translationTask(_:)` even when the configuration values are identical
    /// to the previous run.
    private(set) var generation: Int = 0
    private(set) var pendingConfiguration: TranslationSession.Configuration?
    private(set) var pendingText: String?
    private var continuation: CheckedContinuation<String, Error>?

    private init() {}

    func translate(
        text: String,
        source: Locale.Language?,
        target: Locale.Language
    ) async throws -> String {
        // Cancel any in-flight request that was abandoned.
        if let stale = continuation {
            continuation = nil
            stale.resume(throwing: CancellationError())
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            self.continuation = cont
            self.pendingText = text
            if #available(macOS 26.4, *) {
                self.pendingConfiguration = TranslationSession.Configuration(
                    source: source,
                    target: target,
                    preferredStrategy: .lowLatency
                )
            } else {
                self.pendingConfiguration = TranslationSession.Configuration(
                    source: source,
                    target: target
                )
            }
            self.generation &+= 1
        }
    }

    /// Called by the driver view once the SwiftUI translation task completes.
    func deliver(_ result: Result<String, Error>) {
        let cont = continuation
        continuation = nil
        pendingText = nil
        pendingConfiguration = nil
        switch result {
        case .success(let s): cont?.resume(returning: s)
        case .failure(let e): cont?.resume(throwing: e)
        }
    }
}

/// Hidden host view that lets `TranslationSession` run inside a SwiftUI
/// hierarchy. Place it as an overlay anywhere — it draws nothing.
struct NativeTranslationDriverView: View {
    @State private var coord = NativeTranslationCoordinator.shared

    var body: some View {
        // A zero-size Color keeps the view in the hierarchy without affecting
        // layout. The translationTask modifier needs a host.
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .translationTask(coord.pendingConfiguration) { session in
                guard let text = coord.pendingText else { return }
                do {
                    let response = try await session.translate(text)
                    coord.deliver(.success(response.targetText))
                } catch {
                    coord.deliver(.failure(error))
                }
            }
            // Re-fire the task when the user issues a fresh translate even if
            // the configuration values are byte-identical to the previous run.
            .id(coord.generation)
    }
}
