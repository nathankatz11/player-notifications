import Foundation
import Observation

/// App-wide surface for user-visible, non-blocking error messages.
///
/// View models route failures here from their `catch` blocks so the user sees
/// a transient toast instead of a silent spinner or stale data. The view layer
/// (see `StatShotApp`'s `ContentView`) observes `message`, renders it via
/// `ToastView`, and auto-dismisses after a short delay.
///
/// Deep-link failures also flow through here (see `DeepLinkCoordinator`), so
/// there's a single place the UI reads from.
@MainActor
@Observable
final class AppErrorCoordinator {
    static let shared = AppErrorCoordinator()

    /// The message currently shown in the toast, or `nil` when no toast is up.
    var message: String?

    private init() {}

    /// Surface a user-visible error. If the same message is already showing,
    /// this is a no-op — prevents flicker when two parallel requests fail with
    /// the same error (e.g. a `loadAlerts` that fans out to two endpoints).
    func report(_ message: String) {
        guard self.message != message else { return }
        self.message = message
    }

    /// Clear the toast. Called by the auto-dismiss timer and tap-to-dismiss.
    func clear() {
        message = nil
    }
}

/// Translates an arbitrary thrown error into a short, user-friendly sentence
/// suitable for a toast. Covers the app's `APIError` cases and the common
/// `URLError` connectivity failures; falls back to `localizedDescription`.
///
/// Returns `nil` for cancellations (debounced search tasks, sheet-dismiss
/// aborts, etc.) — those aren't user-facing errors and shouldn't spam toasts.
func friendlyMessage(for error: Error) -> String? {
    // Swift Task cancellation — never user-facing.
    if error is CancellationError { return nil }

    if let api = error as? APIError {
        switch api {
        case .invalidResponse:
            return "Something went wrong. Please try again."
        case .httpError(let code):
            return "Server error (\(code))."
        case .serverMessage(let msg):
            return msg
        }
    }
    if let urlErr = error as? URLError {
        switch urlErr.code {
        case .cancelled:
            return nil
        case .notConnectedToInternet, .networkConnectionLost:
            return "You're offline. Check your connection."
        case .timedOut:
            return "The request timed out."
        default:
            return "Network error: \(urlErr.localizedDescription)"
        }
    }
    return error.localizedDescription
}
