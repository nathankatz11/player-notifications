import Foundation

/// Handles all Firestore CRUD operations.
/// TODO: Import FirebaseFirestore once Firebase SDK is added via SPM.
final class FirebaseService {
    static let shared = FirebaseService()

    private init() {}

    // MARK: - Subscriptions

    func getSubscriptions(forUser userId: String) async throws -> [Subscription] {
        // TODO: Query Firestore /subscriptions where userId == userId && active == true
        return []
    }

    func createSubscription(_ subscription: Subscription) async throws {
        // TODO: Add to Firestore /subscriptions collection
    }

    func updateSubscription(id: String, active: Bool) async throws {
        // TODO: Update Firestore /subscriptions/{id}
    }

    // MARK: - Alerts

    func getAlertHistory(forUser userId: String, daysBack: Int) async throws -> [AlertItem] {
        // TODO: Query Firestore /alerts where userId == userId, ordered by sentAt desc
        // Free: 7 days, Premium: 90 days
        return []
    }

    // MARK: - User

    func getUser(id: String) async throws -> AppUser? {
        // TODO: Fetch from Firestore /users/{id}
        return nil
    }

    func updateFCMToken(userId: String, token: String) async throws {
        // TODO: Update Firestore /users/{userId} fcmToken field
    }
}
