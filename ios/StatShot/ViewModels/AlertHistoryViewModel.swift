import Foundation
import Observation

@Observable
final class AlertHistoryViewModel {
    var alerts: [AlertItem] = []
    var isLoading = false
    var errorMessage: String?

    func loadAlerts() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Fetch from Firestore via FirebaseService
        // Free tier: last 7 days
        // Premium: last 90 days
    }
}
