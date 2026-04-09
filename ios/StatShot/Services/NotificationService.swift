import Foundation
import UserNotifications

/// Handles push notification registration and permission requests.
/// TODO: Import FirebaseMessaging once Firebase SDK is added via SPM.
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    // TODO: Register for remote notifications
                    // UIApplication.shared.registerForRemoteNotifications()
                }
            }

            if let error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        // TODO: Pass device token to Firebase Messaging
        // Messaging.messaging().apnsToken = deviceToken
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(token)")
    }

    func handleFCMToken(_ token: String) {
        // TODO: Store FCM token in Firestore for the current user
        // try await FirebaseService.shared.updateFCMToken(userId: userId, token: token)
        print("FCM token: \(token)")
    }
}
