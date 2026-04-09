import Foundation
import Observation

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
        isLoading = true
        defer { isLoading = false }

        // TODO: Fetch from Firestore via FirebaseService
        // subscriptions = try await FirebaseService.shared.getSubscriptions()
    }

    func searchEntities() async {
        guard searchQuery.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        // TODO: Call backend searchEntity function
        // searchResults = try await APIService.shared.search(query: searchQuery, league: selectedLeague)
    }

    func createSubscription(
        type: SubscriptionType,
        league: League,
        entityId: String,
        entityName: String,
        trigger: TriggerType,
        deliveryMethod: DeliveryMethod
    ) async {
        // TODO: Call backend manageSubscription function
        // Enforce free tier limit client-side too (3 max)
    }

    func toggleSubscription(_ subscription: Subscription) async {
        // TODO: Update subscription active state
    }

    func deleteSubscription(_ subscription: Subscription) async {
        // TODO: Deactivate subscription via backend
    }
}

struct SearchResult: Identifiable {
    let id: String
    let name: String
    let type: String // "player" or "team"
    let league: String
    let imageUrl: String?
}
