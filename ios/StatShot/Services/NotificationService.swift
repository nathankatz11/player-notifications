import Foundation
import UserNotifications

/// Handles APNs push notification registration and permission requests.
/// Sends device token to the Vercel backend for direct APNs delivery.
final class NotificationService: NSObject, @unchecked Sendable {
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
                    // TODO: Uncomment when running on a real device
                    // UIApplication.shared.registerForRemoteNotifications()
                }
            }

            if let error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(token)")

        // Store locally and send to backend on next register/login
        UserDefaults.standard.set(token, forKey: "statshot_apns_token")
    }

    var storedAPNsToken: String? {
        UserDefaults.standard.string(forKey: "statshot_apns_token")
    }
}
