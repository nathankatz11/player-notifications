import Foundation
import Observation

@MainActor
@Observable
final class AlertHistoryViewModel {
    var alerts: [AlertItem] = []
    var isLoading = false
    var errorMessage: String?

    func loadAlerts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let userId = AuthService.shared.currentUserId else {
            errorMessage = "Please sign in to view alert history."
            return
        }

        do {
            alerts = try await APIService.shared.getAlertHistory(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
