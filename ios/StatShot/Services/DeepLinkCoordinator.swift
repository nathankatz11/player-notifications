import Foundation
import Observation

/// Single source of truth for pending deep-link targets produced by APNs
/// notification taps. Set from `NotificationService`'s `didReceive` delegate
/// and consumed by views (notably the Alerts tab) once they're mounted and
/// have the data they need to navigate.
///
/// Holding the pending id here (instead of routing directly to a view) handles
/// the cold-start case: `didReceive` can fire before any view has mounted, and
/// the id waits here until a view observes `pendingSubscriptionId` and calls
/// `consume()`.
@MainActor
@Observable
final class DeepLinkCoordinator {
    static let shared = DeepLinkCoordinator()

    /// The subscription id the user just tapped a notification for, or nil.
    /// Views observe this with `.onChange(of:)` and call `consume()` once
    /// they've navigated.
    var pendingSubscriptionId: String?

    /// A user-visible error string shown as a toast when a deep link fails to
    /// resolve (e.g. the referenced subscription was deleted before the user
    /// tapped the notification). Views read this and render it above the UI;
    /// it auto-clears on a timer.
    var toastMessage: String?

    private init() {}

    /// Record a deep-link request. Safe to call repeatedly; the latest tap wins.
    func request(subscriptionId: String) {
        pendingSubscriptionId = subscriptionId
    }

    /// Atomically read-and-clear the pending target. Returns nil if nothing
    /// is pending.
    func consume() -> String? {
        defer { pendingSubscriptionId = nil }
        return pendingSubscriptionId
    }

    /// Surface a user-visible failure message (e.g. "deep link couldn't
    /// resolve"). Callers typically follow up by calling `consume()` to clear
    /// the pending id.
    func reportFailure(_ message: String) {
        toastMessage = message
    }

    /// Clear the toast. Called by the auto-dismiss timer in the view layer.
    func clearToast() {
        toastMessage = nil
    }
}
