import Foundation
import Observation

@MainActor
@Observable
final class SubscriptionViewModel {
    var subscriptions: [Subscription] = []
    var isLoading = false
    var errorMessage: String?

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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
        guard let userId = AuthService.shared.currentUserId else { return }

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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func deleteSubscription(_ subscription: Subscription) async {
        do {
            try await APIService.shared.deleteSubscription(id: subscription.id)
            subscriptions.removeAll { $0.id == subscription.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SearchResult: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String // "player" or "team"
    let imageUrl: String?
}
