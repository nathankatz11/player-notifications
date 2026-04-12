import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionViewModel {
    var subscriptions: [Subscription] = []
    var isLoading = false
    var errorMessage: String?

    // Teams state
    var teams: [Team] = []
    var isLoadingTeams = false

    // Trending state
    var trendingPlayers: [TrendingPlayer] = []

    // Search state for AddAlertView
    var searchQuery = ""
    var searchResults: [SearchResult] = []
    var isSearching = false
    var selectedLeague: League = .nba

    func loadSubscriptions() async {
        guard let userId = AuthService.shared.currentUserId else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            subscriptions = try await APIService.shared.getSubscriptions(userId: userId)
        } catch {
            let friendly = friendlyMessage(for: error)
            errorMessage = friendly
            AppErrorCoordinator.shared.report(friendly)
        }
    }

    func loadTeams() async {
        isLoadingTeams = true
        defer { isLoadingTeams = false }

        do {
            teams = try await APIService.shared.fetchTeams(league: selectedLeague.rawValue)
        } catch {
            teams = []
            let friendly = friendlyMessage(for: error)
            errorMessage = friendly
            AppErrorCoordinator.shared.report(friendly)
        }
    }

    func loadTrending() async {
        do {
            trendingPlayers = try await APIService.shared.fetchTrending(league: selectedLeague.rawValue)
        } catch {
            trendingPlayers = []
        }
    }

    func searchEntities() async {
        guard searchQuery.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            searchResults = try await APIService.shared.search(
                query: searchQuery,
                league: selectedLeague.rawValue
            )
        } catch {
            let friendly = friendlyMessage(for: error)
            errorMessage = friendly
            AppErrorCoordinator.shared.report(friendly)
        }
    }

    func createSubscription(
        type: SubscriptionType,
        league: League,
        entityId: String,
        entityName: String,
        trigger: TriggerType,
        deliveryMethod: DeliveryMethod
    ) async {
        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "Please sign in first (Settings → Sign In)"
            return
        }

        do {
            let params = CreateSubscriptionParams(
                userId: userId,
                type: type.rawValue,
                league: league.rawValue,
                entityId: entityId,
                entityName: entityName,
                trigger: trigger.rawValue,
                deliveryMethod: deliveryMethod.rawValue
            )
            _ = try await APIService.shared.createSubscription(params)
            await loadSubscriptions()
        } catch {
            let friendly = friendlyMessage(for: error)
            errorMessage = friendly
            AppErrorCoordinator.shared.report(friendly)
        }
    }

    func toggleSubscription(_ subscription: Subscription) async {
        do {
            try await APIService.shared.updateSubscription(
                id: subscription.id,
                active: !subscription.active
            )
            if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[index].active.toggle()
            }
        } catch {
            let friendly = friendlyMessage(for: error)
            errorMessage = friendly
            AppErrorCoordinator.shared.report(friendly)
        }
    }

    func deleteSubscription(_ subscription: Subscription) async {
        do {
            try await APIService.shared.deleteSubscription(id: subscription.id)
            subscriptions.removeAll { $0.id == subscription.id }
        } catch {
            let friendly = friendlyMessage(for: error)
            errorMessage = friendly
            AppErrorCoordinator.shared.report(friendly)
        }
    }
}

struct SearchResult: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String // "player" or "team"
    let imageUrl: String?
}
