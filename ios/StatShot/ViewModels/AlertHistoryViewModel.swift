import Foundation
import Observation

@MainActor
@Observable
final class AlertHistoryViewModel {
    var alerts: [AlertItem] = []
    var subscriptionsById: [String: Subscription] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastSeenAt: Date?

    /// Leagues currently selected in the filter menu. Empty set means "show all".
    var selectedLeagues: Set<League> = []

    private let lastSeenKey = "statshot_last_seen_alert_at"

    init() {
        self.lastSeenAt = UserDefaults.standard.object(forKey: lastSeenKey) as? Date
    }

    func loadAlerts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "Please sign in to view alert history."
            return
        }

        do {
            async let alertsTask = APIService.shared.getAlertHistory(userId: userId)
            async let subsTask = APIService.shared.getSubscriptions(userId: userId)

            let (loadedAlerts, loadedSubs) = try await (alertsTask, subsTask)
            self.alerts = loadedAlerts

            var map: [String: Subscription] = [:]
            for sub in loadedSubs {
                map[sub.id] = sub
            }
            self.subscriptionsById = map
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func subscription(for alert: AlertItem) -> Subscription? {
        subscriptionsById[alert.subscriptionId]
    }

    func isUnread(_ alert: AlertItem) -> Bool {
        guard let seen = lastSeenAt else { return true }
        return alert.sentAt > seen
    }

    func markAllAsSeen() {
        let now = Date()
        lastSeenAt = now
        UserDefaults.standard.set(now, forKey: lastSeenKey)
    }

    // MARK: - Filtering

    /// Whether any league filter is currently active.
    var isFilterActive: Bool {
        !selectedLeagues.isEmpty
    }

    /// Alerts filtered by the current `selectedLeagues`.
    /// - When no filter is active, returns all alerts (including those without a matching subscription).
    /// - When a filter is active, only alerts whose subscription's league is in the selected set are included;
    ///   alerts without a matching subscription are excluded.
    var filteredAlerts: [AlertItem] {
        guard isFilterActive else { return alerts }
        return alerts.filter { alert in
            guard let sub = subscription(for: alert) else { return false }
            return selectedLeagues.contains(sub.league)
        }
    }

    func toggleLeague(_ league: League) {
        if selectedLeagues.contains(league) {
            selectedLeagues.remove(league)
        } else {
            selectedLeagues.insert(league)
        }
    }

    func clearLeagueFilter() {
        selectedLeagues.removeAll()
    }

    // MARK: - Mute / Unmute

    /// Toggles the `active` flag on a subscription via the API and updates local state on success.
    /// Returns the new `active` value, or `nil` on failure.
    @discardableResult
    func setSubscriptionActive(_ subscription: Subscription, active: Bool) async -> Bool? {
        do {
            try await APIService.shared.updateSubscription(id: subscription.id, active: active)
            var updated = subscription
            updated.active = active
            subscriptionsById[subscription.id] = updated
            return active
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
