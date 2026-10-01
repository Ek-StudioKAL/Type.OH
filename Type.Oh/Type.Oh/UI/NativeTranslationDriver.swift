import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Whether the native macOS Translation framework (macOS 15+) can be used at
/// runtime. On older releases the `.nativeOS` engine is hidden and any stored
/// selection falls back to the cloud engine.
enum NativeTranslationSupport {
    static var isAvailable: Bool {
        #if canImport(Translation)
        if #available(macOS 15.0, *) { return true }
        #endif
        return false
    }
}

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
final class NativeTranslationCoordinator: ObservableObject {
    static let shared = NativeTranslationCoordinator()

    /// Bumped on every new request so SwiftUI re-evaluates the
    /// `.translationTask(_:)` even when the configuration values are identical
    /// to the previous run.
    @Published private(set) var generation: Int = 0
    /// A `TranslationSession.Configuration` when the framework exists. Stored
    /// type-erased because stored properties can't carry an availability
    /// narrower than their type.
    @Published private(set) var pendingConfigurationBox: Any?
    @Published private(set) var pendingText: String?
    private var continuation: CheckedContinuation<String, Error>?

    private init() {}

    func translate(
        text: String,
        source: Locale.Language?,
        target: Locale.Language
    ) async throws -> String {
        guard NativeTranslationSupport.isAvailable else {
            throw TranslationDispatcher.Failure.nativeUnavailable
        }
        // Cancel any in-flight request that was abandoned.
        if let stale = continuation {
            continuation = nil
            stale.resume(throwing: CancellationError())
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            self.continuation = cont
            self.pendingText = text
            #if canImport(Translation)
            if #available(macOS 26.4, *) {
                self.pendingConfigurationBox = TranslationSession.Configuration(
                    source: source,
                    target: target,
                    preferredStrategy: .lowLatency
                )
            } else if #available(macOS 15.0, *) {
                self.pendingConfigurationBox = TranslationSession.Configuration(
                    source: source,
                    target: target
                )
            }
            #endif
            self.generation &+= 1
        }
    }

    /// Called by the driver view once the SwiftUI translation task completes.
    func deliver(_ result: Result<String, Error>) {
        let cont = continuation
        continuation = nil
        pendingText = nil
        pendingConfigurationBox = nil
        switch result {
        case .success(let s): cont?.resume(returning: s)
        case .failure(let e): cont?.resume(throwing: e)
        }
    }
}

/// Hidden host view that lets `TranslationSession` run inside a SwiftUI
/// hierarchy. Place it as an overlay anywhere — it draws nothing. On macOS
/// releases without the Translation framework it is an empty view.
@MainActor struct NativeTranslationDriverView: View {
    var body: some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            NativeTranslationDriverBody()
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
@MainActor private struct NativeTranslationDriverBody: View {
    @ObservedObject private var coord = NativeTranslationCoordinator.shared

    var body: some View {
        // A zero-size Color keeps the view in the hierarchy without affecting
        // layout. The translationTask modifier needs a host.
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .translationTask(coord.pendingConfigurationBox as? TranslationSession.Configuration) { session in
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
#endif
