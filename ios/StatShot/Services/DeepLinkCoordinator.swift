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
}
